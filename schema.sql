-- ZenSched Fire-Safety Local Database Schema
-- SQLite database for clients (property managers, building owners, facility
-- firms), contracted buildings (the places), the device inventory
-- (extinguisher / emergency light / exit sign / hose), technicians, one
-- inspection visit per building, per-device results copied from the Device
-- Inspection form, and client invoices.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my firesafe-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 firesafe-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- THIS IS NOT AN AHJ E-FILE TOOL and not the official / statutory service
-- record (NFPA 10 / OSHA 1910.157, BS 5306-3 / BS 5266-1, AS 1851 / AS 2293.2).
-- It does not submit to a fire marshal, a building department, The Compliance
-- Engine, Brycer, or any authority-having-jurisdiction portal. inspections +
-- device_results are YOUR local visit notes (who was there, GPS times,
-- pass / fail / serviced per tag) — not the official logbook and not a
-- replacement for the tag on the cylinder. You (or the client) still file
-- whatever the AHJ wants, on their form.
--
-- PRIVACY: buildings.access_notes (lockbox, fire-panel code, after-hours
-- contact) and technicians.license_no live ONLY in this file on your computer.
-- ZenSched receives, per building, a short label (the building name or
-- street), the street address for the GPS pin, a matching event title, and
-- the Device Inspection form the tech fills in (tag, type, result, tag
-- photo, fail notes). SKILL.md forbids the agent from putting any local-only
-- column into a ZenSched field.
--
-- PHOTOS: ZenSched stores the upload and the GPS punch separately. It does
-- NOT burn a date, time, or GPS stamp onto the image pixels.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, defaults, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Fire Safety Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_tech_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '90');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_travel_buffer_minutes', '20');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('inspection_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');

-- Clients: who hires you and who pays you. A property manager, a building
-- owner, a facility-management firm, or an HOA. payment_terms_days drives
-- invoice due dates; default_visit_fee / default_travel_fee are copied onto
-- an inspection when the agent leaves fees NULL.
CREATE TABLE IF NOT EXISTS clients (
  client_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_name TEXT NOT NULL,
  client_type TEXT NOT NULL DEFAULT 'property_manager'
    CHECK (client_type IN ('property_manager', 'building_owner', 'facility_firm', 'hoa', 'other')),
  contact_name TEXT,                                -- LOCAL ONLY: the site / accounts contact
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER NOT NULL DEFAULT 30,
  default_visit_fee REAL,                           -- $ per completed building visit
  default_travel_fee REAL,                          -- $ wasted-journey / travel
  notes TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Buildings: the places. One contracted site, one ZenSched LOCATION (created
-- once and kept forever), one rolling ZenSched EVENT of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a visit date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
-- visit_frequency + next_visit_date drive "schedule this week".
-- access_notes is LOCAL ONLY.
CREATE TABLE IF NOT EXISTS buildings (
  building_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  building_name TEXT NOT NULL,                      -- 'Riverside Plaza'
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  region TEXT,                                      -- state / county
  postcode TEXT,
  country TEXT NOT NULL DEFAULT 'US'
    CHECK (country IN ('US', 'UK', 'AU', 'CA', 'IE', 'NZ', 'other')),
  street_name TEXT,                                 -- '400 Oak Street' (number + street)
  building_label TEXT,                              -- name sent to ZenSched; default building_name
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  access_notes TEXT,                                -- LOCAL ONLY: lockbox, fire panel, after-hours
  visit_frequency TEXT NOT NULL DEFAULT 'monthly'
    CHECK (visit_frequency IN ('monthly', 'quarterly', 'annual', 'on-demand')),
  next_visit_date TEXT,                             -- ISO date: '2026-09-10'
  last_visit_date TEXT,                             -- set when an inspection is completed
  preferred_start TEXT                              -- 'HH:MM' 24-hour local; NULL = 09:00
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  visit_minutes INTEGER                             -- NULL -> settings.default_visit_minutes
    CHECK (visit_minutes IS NULL OR visit_minutes BETWEEN 15 AND 480),
  visit_fee REAL,                                   -- NULL -> client default_visit_fee
  zensched_worker_id INTEGER,                       -- preferred tech; NULL = settings.default_tech
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Devices: the contracted inventory at a building. device_tag is what the
-- tech types on the Device Inspection form (FE-12, EL-3A). device_type is
-- the four kit types. last_result / last_inspected_at are filled by trigger
-- from the latest device_results row so "what's failed at Riverside" is a
-- local query. location_note is the floor / stair / riser, local only.
CREATE TABLE IF NOT EXISTS devices (
  device_id INTEGER PRIMARY KEY AUTOINCREMENT,
  building_id INTEGER NOT NULL,
  device_tag TEXT NOT NULL,                         -- as stamped on the unit; matched to the form
  device_type TEXT NOT NULL
    CHECK (device_type IN ('extinguisher', 'light', 'exit', 'hose')),
  location_note TEXT,                               -- LOCAL: 'Floor 2 stairwell A'
  manufacturer TEXT,
  size_note TEXT,                                   -- '10 lb ABC', '2.5 in', ...
  manufacture_year INTEGER,
  last_result TEXT
    CHECK (last_result IS NULL OR last_result IN ('pass', 'fail', 'serviced')),
  last_inspected_at TEXT,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (building_id) REFERENCES buildings(building_id) ON DELETE CASCADE,
  UNIQUE (building_id, device_tag)
);

-- Technicians: in solo mode this is one row (you) whose zensched_worker_id
-- came from inviting yourself. license_no is LOCAL ONLY (state / NICET /
-- competent-person number) and never sent to ZenSched.
CREATE TABLE IF NOT EXISTS technicians (
  technician_id INTEGER PRIMARY KEY AUTOINCREMENT,
  technician_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  is_owner INTEGER DEFAULT 0,
  license_no TEXT,                                  -- LOCAL ONLY
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Inspections: one row per BUILDING visit (one ZenSched shift). Created when
-- the week is scheduled (status = scheduled) and closed when the tech
-- checks out and the Device Inspection submissions are recorded.
-- The event lives on the building (60-day roll), not on this row — this row
-- only stores the event_id that was current when the shift was created.
--
-- inspection_no is INSP-YYYY-0001 (INV- is reserved for invoices).
--
-- scheduled_start is LOCAL wall-clock time as 'YYYY-MM-DDTHH:MM' or
-- 'YYYY-MM-DDTHH:MM:SS' with NO offset and no 'Z'; the views append
-- settings.timezone_offset to produce start_iso / end_iso for shift_create.
--
-- Fees are per-visit snapshots. Leave them NULL on insert and the
-- fill_inspection_defaults trigger copies the building / client defaults.
CREATE TABLE IF NOT EXISTS inspections (
  inspection_id INTEGER PRIMARY KEY AUTOINCREMENT,
  inspection_no TEXT UNIQUE,                        -- 'INSP-2026-0001', filled by trigger if NULL
  client_id INTEGER NOT NULL,
  building_id INTEGER NOT NULL,
  scheduled_start TEXT NOT NULL                     -- local 'YYYY-MM-DDTHH:MM[:SS]', no offset
    CHECK (scheduled_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-2][0-9]:[0-5][0-9]*'
           AND scheduled_start NOT GLOB '*T*[+-]*'
           AND scheduled_start NOT GLOB '*Z'),
  duration_minutes INTEGER                          -- NULL -> building.visit_minutes / settings
    CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 15 AND 480),
  technician_id INTEGER,                            -- NULL -> settings.default_tech_id (trigger)
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'completed', 'missed', 'cancelled')),
  visit_fee REAL,                                   -- NULL -> building then client default
  travel_fee REAL,                                  -- NULL -> client default_travel_fee
  other_fee REAL,                                   -- extra service, wait, late-cancel
  zensched_event_id INTEGER,                        -- building's event at shift-create time
  zensched_shift_id INTEGER UNIQUE,                 -- one shift per building visit
  checked_in_at TEXT,                               -- from shift_status (ISO with offset)
  checked_out_at TEXT,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  checkin_distance_m INTEGER,
  notes TEXT,
  invoiced INTEGER DEFAULT 0,
  exported_at TEXT,                                 -- when the client pack was produced (not an AHJ filing)
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (building_id) REFERENCES buildings(building_id) ON DELETE RESTRICT,
  FOREIGN KEY (technician_id) REFERENCES technicians(technician_id) ON DELETE SET NULL
);

-- Device results: one row per Device Inspection form submission (one device
-- per submit) on a building visit. The agent matches device_tag to devices
-- for that building (case-insensitive); device_id stays NULL for an unknown
-- tag so the owner can add the unit later. report_dc_id is the ZenSched
-- submission id (UNIQUE so the same submit is never stored twice).
-- result / device_type store the form option keys (pass/fail/serviced,
-- extinguisher/light/exit/hose).
CREATE TABLE IF NOT EXISTS device_results (
  result_id INTEGER PRIMARY KEY AUTOINCREMENT,
  inspection_id INTEGER NOT NULL,
  device_id INTEGER,                                -- NULL if the typed tag is not on the building
  device_tag TEXT NOT NULL,                         -- as the tech typed it
  device_type TEXT NOT NULL
    CHECK (device_type IN ('extinguisher', 'light', 'exit', 'hose')),
  result TEXT NOT NULL
    CHECK (result IN ('pass', 'fail', 'serviced')),
  fail_notes TEXT,
  photo_count INTEGER,
  report_dc_id INTEGER UNIQUE,                      -- Device Inspection submission_id
  resolved_at TEXT,                                 -- set when a later pass/serviced lands, or by owner
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (inspection_id) REFERENCES inspections(inspection_id) ON DELETE CASCADE,
  FOREIGN KEY (device_id) REFERENCES devices(device_id) ON DELETE SET NULL,
  UNIQUE (inspection_id, device_tag)
);

-- Invoices: one per client per billing run. invoice_number is filled by trigger
-- if left NULL (INV-YYYY-0001 — different prefix from inspection_no). due_date
-- is invoice_date + the client's payment_terms_days. line_items is a JSON
-- array with one object per inspection so the invoice can be regenerated.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_buildings_client ON buildings(client_id, is_active);
CREATE INDEX IF NOT EXISTS idx_buildings_next ON buildings(next_visit_date, is_active);
CREATE INDEX IF NOT EXISTS idx_buildings_location ON buildings(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_buildings_event ON buildings(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_devices_building ON devices(building_id, is_active);
CREATE INDEX IF NOT EXISTS idx_devices_tag ON devices(building_id, device_tag);
CREATE INDEX IF NOT EXISTS idx_devices_last_result ON devices(last_result, is_active);
CREATE INDEX IF NOT EXISTS idx_technicians_worker ON technicians(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_inspections_start ON inspections(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_inspections_status_start ON inspections(status, scheduled_start);
CREATE INDEX IF NOT EXISTS idx_inspections_client ON inspections(client_id, invoiced);
CREATE INDEX IF NOT EXISTS idx_inspections_building ON inspections(building_id);
CREATE INDEX IF NOT EXISTS idx_inspections_event ON inspections(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_inspections_export ON inspections(status, exported_at);
CREATE INDEX IF NOT EXISTS idx_device_results_inspection ON device_results(inspection_id);
CREATE INDEX IF NOT EXISTS idx_device_results_device ON device_results(device_id, result);
CREATE INDEX IF NOT EXISTS idx_device_results_open_fail ON device_results(result, resolved_at);
CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid, due_date);

-- Which fees are billable depends on what happened. This is the single place
-- that rule lives; receivables and invoicing read billable_total from here.
--   completed  -> visit + travel + other
--   missed     -> travel_fee only                  (wasted journey)
--   cancelled  -> other_fee only                   (a late-cancel fee in other_fee)
--   scheduled  -> 0
CREATE VIEW IF NOT EXISTS billable_inspections AS
SELECT
  i.inspection_id,
  i.inspection_no,
  i.client_id,
  i.building_id,
  i.status,
  date(i.scheduled_start)                          AS inspection_date,
  i.scheduled_start,
  i.technician_id,
  i.visit_fee,
  i.travel_fee,
  i.other_fee,
  CASE i.status
    WHEN 'completed' THEN round(COALESCE(i.visit_fee, 0) + COALESCE(i.travel_fee, 0) + COALESCE(i.other_fee, 0), 2)
    WHEN 'missed'    THEN round(COALESCE(i.travel_fee, 0), 2)
    WHEN 'cancelled' THEN round(COALESCE(i.other_fee, 0), 2)
    ELSE 0
  END                                              AS billable_total,
  i.invoiced,
  i.zensched_shift_id,
  i.zensched_event_id
FROM inspections i;

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_client_timestamp
AFTER UPDATE ON clients
BEGIN
  UPDATE clients SET updated_at = datetime('now') WHERE client_id = NEW.client_id;
END;

CREATE TRIGGER IF NOT EXISTS update_building_timestamp
AFTER UPDATE ON buildings
BEGIN
  UPDATE buildings SET updated_at = datetime('now') WHERE building_id = NEW.building_id;
END;

CREATE TRIGGER IF NOT EXISTS update_device_timestamp
AFTER UPDATE OF building_id, device_tag, device_type, location_note, manufacturer,
                size_note, manufacture_year, last_result, last_inspected_at, is_active, notes
ON devices
BEGIN
  UPDATE devices SET updated_at = datetime('now') WHERE device_id = NEW.device_id;
END;

CREATE TRIGGER IF NOT EXISTS update_technician_timestamp
AFTER UPDATE ON technicians
BEGIN
  UPDATE technicians SET updated_at = datetime('now') WHERE technician_id = NEW.technician_id;
END;

CREATE TRIGGER IF NOT EXISTS update_inspection_timestamp
AFTER UPDATE OF client_id, building_id, scheduled_start, duration_minutes, technician_id,
                status, visit_fee, travel_fee, other_fee, zensched_event_id, zensched_shift_id,
                checked_in_at, checked_out_at, gps_verified, checkin_distance_m, notes,
                invoiced, exported_at
ON inspections
BEGIN
  UPDATE inspections SET updated_at = datetime('now') WHERE inspection_id = NEW.inspection_id;
END;

-- Auto-number inspections: INSP-2026-0001, INSP-2026-0002, ... (year of the
-- visit, sequence = inspection_id). Do NOT use INV- — that is invoices.
CREATE TRIGGER IF NOT EXISTS number_inspection
AFTER INSERT ON inspections
WHEN NEW.inspection_no IS NULL
BEGIN
  UPDATE inspections
  SET inspection_no = 'INSP-' || strftime('%Y', NEW.scheduled_start) || '-' || printf('%04d', NEW.inspection_id)
  WHERE inspection_id = NEW.inspection_id;
END;

-- Fill defaults the agent left NULL:
--   duration_minutes <- building.visit_minutes, else settings.default_visit_minutes (else 90)
--   technician_id    <- settings.default_tech_id (solo mode: you)
--   visit_fee        <- building.visit_fee, else client's default_visit_fee, else 0
--   travel_fee       <- client's default_travel_fee, else 0
--   other_fee        <- 0
-- Fees are snapshots: changing a client's defaults later never rewrites history.
CREATE TRIGGER IF NOT EXISTS fill_inspection_defaults
AFTER INSERT ON inspections
BEGIN
  UPDATE inspections
  SET duration_minutes = COALESCE(NEW.duration_minutes,
                                  (SELECT visit_minutes FROM buildings WHERE building_id = NEW.building_id),
                                  (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_visit_minutes'),
                                  90),
      technician_id = COALESCE(NEW.technician_id,
                               (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_tech_id' AND value IS NOT NULL)),
      visit_fee = COALESCE(NEW.visit_fee,
                           (SELECT visit_fee FROM buildings WHERE building_id = NEW.building_id),
                           (SELECT default_visit_fee FROM clients WHERE client_id = NEW.client_id),
                           0),
      travel_fee = COALESCE(NEW.travel_fee, (SELECT default_travel_fee FROM clients WHERE client_id = NEW.client_id), 0),
      other_fee  = COALESCE(NEW.other_fee, 0)
  WHERE inspection_id = NEW.inspection_id;
END;

-- Completing an inspection advances the building's cadence.
-- quarterly is +90 days (not +3 months). annual is +1 year. on-demand clears
-- the next date. The agent should NOT hand-maintain next_visit_date after this.
CREATE TRIGGER IF NOT EXISTS advance_next_visit_on_complete
AFTER UPDATE OF status ON inspections
WHEN NEW.status = 'completed' AND OLD.status <> 'completed'
BEGIN
  UPDATE buildings
  SET last_visit_date = date(NEW.scheduled_start),
      next_visit_date = CASE visit_frequency
        WHEN 'monthly'    THEN date(NEW.scheduled_start, '+1 month')
        WHEN 'quarterly'  THEN date(NEW.scheduled_start, '+90 days')
        WHEN 'annual'     THEN date(NEW.scheduled_start, '+1 year')
        ELSE NULL
      END
  WHERE building_id = NEW.building_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Link a result to the building's device by tag (case-insensitive) when the
-- agent left device_id NULL; stamp last_result / last_inspected_at on that
-- device; resolve prior open fails when this result is pass or serviced.
CREATE TRIGGER IF NOT EXISTS fill_device_from_result
AFTER INSERT ON device_results
BEGIN
  UPDATE device_results
  SET device_id = COALESCE(NEW.device_id, (
        SELECT d.device_id FROM devices d
        JOIN inspections i ON i.inspection_id = NEW.inspection_id
        WHERE d.building_id = i.building_id
          AND lower(d.device_tag) = lower(NEW.device_tag)
          AND d.is_active = 1
      ))
  WHERE result_id = NEW.result_id;
  UPDATE devices
  SET last_result = NEW.result,
      last_inspected_at = datetime('now')
  WHERE device_id = (SELECT device_id FROM device_results WHERE result_id = NEW.result_id)
    AND (SELECT device_id FROM device_results WHERE result_id = NEW.result_id) IS NOT NULL;
  UPDATE device_results
  SET resolved_at = datetime('now')
  WHERE result = 'fail'
    AND resolved_at IS NULL
    AND NEW.result IN ('pass', 'serviced')
    AND result_id != NEW.result_id
    AND device_id = (SELECT device_id FROM device_results WHERE result_id = NEW.result_id)
    AND device_id IS NOT NULL;
END;

-- Buildings due in the next 7 days (today + 6) that do not already have a
-- scheduled or completed inspection on next_visit_date. One row = one
-- inspection insert + one shift_create. start_iso / end_iso carry
-- settings.timezone_offset. event_needs_roll = 1 means create a new ZenSched
-- event first (see SKILL.md). access_notes is included so the agent can tell
-- the owner to pass it to the tech; it must never go into a ZenSched field.
CREATE VIEW IF NOT EXISTS buildings_due AS
SELECT
  b.building_id,
  b.building_name,
  b.client_id,
  c.client_name,
  c.client_type,
  b.visit_frequency,
  b.next_visit_date,
  COALESCE(b.preferred_start, '09:00')                                               AS start_time,
  COALESCE(b.visit_minutes,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_visit_minutes'),
           90)                                                                        AS duration_minutes,
  b.address,
  b.city,
  b.region,
  b.postcode,
  b.country,
  b.address || COALESCE(', ' || b.city, '')
            || COALESCE(', ' || b.region, '')
            || COALESCE(' ' || b.postcode, '')                                       AS street_address,
  COALESCE(b.building_label, b.building_name, b.street_name, b.address)              AS zensched_location_name,
  'Fire safety - ' || COALESCE(b.building_label, b.building_name, b.street_name, b.address)
                                                                                     AS zensched_event_title,
  b.access_notes,
  b.zensched_location_id,
  b.zensched_event_id,
  b.event_valid_until,
  CASE WHEN b.zensched_location_id IS NULL THEN 1 ELSE 0 END                         AS needs_location,
  CASE WHEN b.event_valid_until IS NULL OR b.event_valid_until < b.next_visit_date THEN 1 ELSE 0 END
                                                                                     AS event_needs_roll,
  COALESCE(b.zensched_worker_id,
           (SELECT t.zensched_worker_id FROM technicians t
             WHERE t.technician_id = (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_tech_id')))
                                                                                     AS worker_id,
  (SELECT t.technician_name FROM technicians t
    WHERE t.zensched_worker_id = COALESCE(b.zensched_worker_id,
           (SELECT t2.zensched_worker_id FROM technicians t2
             WHERE t2.technician_id = (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_tech_id'))))
                                                                                     AS technician_name,
  (SELECT COUNT(*) FROM devices d WHERE d.building_id = b.building_id AND d.is_active = 1)
                                                                                     AS device_count,
  b.next_visit_date || 'T' || COALESCE(b.preferred_start, '09:00') || ':00'
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                    AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      b.next_visit_date || ' ' || COALESCE(b.preferred_start, '09:00') || ':00',
      '+' || COALESCE(b.visit_minutes,
                      (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_visit_minutes'),
                      90) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                    AS end_iso,
  'loc-building-' || b.building_id                                                   AS loc_idempotency_key,
  'event-building-' || b.building_id || '-' || strftime('%Y%m%d', b.next_visit_date)  AS event_idempotency_key,
  'shift-building-' || b.building_id || '-' || strftime('%Y%m%d', b.next_visit_date)  AS shift_idempotency_key
FROM buildings b
JOIN clients c ON c.client_id = b.client_id AND c.is_active = 1
WHERE b.is_active = 1
  AND b.next_visit_date IS NOT NULL
  AND b.next_visit_date <= date('now', '+7 days')
  AND NOT EXISTS (
    SELECT 1 FROM inspections i
    WHERE i.building_id = b.building_id
      AND date(i.scheduled_start) = b.next_visit_date
      AND i.status IN ('scheduled', 'completed')
  )
ORDER BY b.next_visit_date, COALESCE(b.preferred_start, '09:00'), b.building_name;

-- Buildings whose current ZenSched event expires within 14 days (or has none)
-- and that still have an active cadence. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  b.building_id,
  b.building_name,
  c.client_name,
  b.address,
  b.zensched_location_id,
  b.zensched_event_id,
  b.event_valid_until,
  COALESCE(b.building_label, b.building_name, b.street_name, b.address)              AS zensched_location_name,
  'Fire safety - ' || COALESCE(b.building_label, b.building_name, b.street_name, b.address)
                                                                                     AS zensched_event_title,
  'event-building-' || b.building_id || '-'
    || strftime('%Y%m%d', COALESCE(date(b.event_valid_until, '+1 day'), date('now', 'localtime')))
                                                                                     AS event_idempotency_key
FROM buildings b
JOIN clients c ON c.client_id = b.client_id AND c.is_active = 1
WHERE b.is_active = 1
  AND (b.event_valid_until IS NULL OR b.event_valid_until <= date('now', '+14 days'))
ORDER BY b.event_valid_until;

-- Today's scheduled inspections (local date of the computer running the
-- database). start_iso / end_iso and the three idempotency keys are ready
-- for the ZenSched calls. needs_shift = 1 means booked locally but never
-- put on the phone.
CREATE VIEW IF NOT EXISTS inspections_today AS
SELECT
  i.inspection_id,
  i.inspection_no,
  i.status,
  i.scheduled_start,
  i.duration_minutes,
  strftime('%Y-%m-%dT%H:%M:%S', i.scheduled_start)
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                     AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(i.scheduled_start, '+' || i.duration_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                     AS end_iso,
  c.client_id,
  c.client_name,
  b.building_id,
  b.building_name,
  b.address || COALESCE(', ' || b.city, '')
            || COALESCE(', ' || b.region, '')
            || COALESCE(' ' || b.postcode, '')                                       AS street_address,
  COALESCE(b.building_label, b.building_name, b.street_name, b.address)              AS zensched_location_name,
  'Fire safety - ' || COALESCE(b.building_label, b.building_name, b.street_name, b.address)
                                                                                     AS zensched_event_title,
  b.access_notes,
  b.zensched_location_id,
  CASE WHEN b.zensched_location_id IS NULL THEN 1 ELSE 0 END                         AS needs_location,
  COALESCE(i.zensched_event_id, b.zensched_event_id)                                 AS zensched_event_id,
  b.event_valid_until,
  CASE WHEN b.event_valid_until IS NULL OR b.event_valid_until < date(i.scheduled_start) THEN 1 ELSE 0 END
                                                                                     AS event_needs_roll,
  i.zensched_shift_id,
  CASE WHEN i.zensched_shift_id IS NULL THEN 1 ELSE 0 END                            AS needs_shift,
  i.technician_id,
  k.technician_name,
  k.zensched_worker_id,
  (SELECT COUNT(*) FROM devices d WHERE d.building_id = b.building_id AND d.is_active = 1)
                                                                                     AS device_count,
  i.visit_fee,
  i.notes,
  'loc-building-' || b.building_id                                                   AS loc_idempotency_key,
  'event-building-' || b.building_id || '-' || strftime('%Y%m%d', i.scheduled_start)  AS event_idempotency_key,
  'shift-building-' || b.building_id || '-' || strftime('%Y%m%d', i.scheduled_start)  AS shift_idempotency_key
FROM inspections i
JOIN clients c ON c.client_id = i.client_id
JOIN buildings b ON b.building_id = i.building_id
LEFT JOIN technicians k ON k.technician_id = i.technician_id
WHERE i.status = 'scheduled'
  AND date(i.scheduled_start) = date('now', 'localtime')
ORDER BY i.scheduled_start;

-- Same columns, next 7 days (today through today + 6).
CREATE VIEW IF NOT EXISTS inspections_upcoming AS
SELECT
  i.inspection_id,
  i.inspection_no,
  i.status,
  i.scheduled_start,
  i.duration_minutes,
  strftime('%Y-%m-%dT%H:%M:%S', i.scheduled_start)
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                     AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(i.scheduled_start, '+' || i.duration_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                     AS end_iso,
  c.client_id,
  c.client_name,
  b.building_id,
  b.building_name,
  b.address || COALESCE(', ' || b.city, '')
            || COALESCE(', ' || b.region, '')
            || COALESCE(' ' || b.postcode, '')                                       AS street_address,
  COALESCE(b.building_label, b.building_name, b.street_name, b.address)              AS zensched_location_name,
  'Fire safety - ' || COALESCE(b.building_label, b.building_name, b.street_name, b.address)
                                                                                     AS zensched_event_title,
  b.access_notes,
  b.zensched_location_id,
  CASE WHEN b.zensched_location_id IS NULL THEN 1 ELSE 0 END                         AS needs_location,
  COALESCE(i.zensched_event_id, b.zensched_event_id)                                 AS zensched_event_id,
  b.event_valid_until,
  CASE WHEN b.event_valid_until IS NULL OR b.event_valid_until < date(i.scheduled_start) THEN 1 ELSE 0 END
                                                                                     AS event_needs_roll,
  i.zensched_shift_id,
  CASE WHEN i.zensched_shift_id IS NULL THEN 1 ELSE 0 END                            AS needs_shift,
  i.technician_id,
  k.technician_name,
  k.zensched_worker_id,
  (SELECT COUNT(*) FROM devices d WHERE d.building_id = b.building_id AND d.is_active = 1)
                                                                                     AS device_count,
  i.visit_fee,
  i.notes,
  'loc-building-' || b.building_id                                                   AS loc_idempotency_key,
  'event-building-' || b.building_id || '-' || strftime('%Y%m%d', i.scheduled_start)  AS event_idempotency_key,
  'shift-building-' || b.building_id || '-' || strftime('%Y%m%d', i.scheduled_start)  AS shift_idempotency_key
FROM inspections i
JOIN clients c ON c.client_id = i.client_id
JOIN buildings b ON b.building_id = i.building_id
LEFT JOIN technicians k ON k.technician_id = i.technician_id
WHERE i.status = 'scheduled'
  AND date(i.scheduled_start) BETWEEN date('now', 'localtime') AND date('now', 'localtime', '+6 days')
ORDER BY i.scheduled_start;

-- Per-inspection pass / fail / serviced counts plus how many active devices
-- on the building were not submitted this visit.
CREATE VIEW IF NOT EXISTS inspection_device_summary AS
SELECT
  i.inspection_id,
  i.inspection_no,
  i.status,
  date(i.scheduled_start)                          AS inspection_date,
  i.building_id,
  b.building_name,
  (SELECT COUNT(*) FROM devices d WHERE d.building_id = i.building_id AND d.is_active = 1)
                                                   AS expected_device_count,
  COUNT(r.result_id)                               AS result_count,
  SUM(CASE WHEN r.result = 'pass' THEN 1 ELSE 0 END)     AS pass_count,
  SUM(CASE WHEN r.result = 'fail' THEN 1 ELSE 0 END)     AS fail_count,
  SUM(CASE WHEN r.result = 'serviced' THEN 1 ELSE 0 END) AS serviced_count,
  (SELECT COUNT(*) FROM devices d
    WHERE d.building_id = i.building_id AND d.is_active = 1
      AND NOT EXISTS (
        SELECT 1 FROM device_results r2
        WHERE r2.inspection_id = i.inspection_id
          AND (r2.device_id = d.device_id OR lower(r2.device_tag) = lower(d.device_tag))
      ))                                           AS missing_count
FROM inspections i
JOIN buildings b ON b.building_id = i.building_id
LEFT JOIN device_results r ON r.inspection_id = i.inspection_id
GROUP BY i.inspection_id
ORDER BY i.scheduled_start;

-- Latest result per device is fail and has not been resolved. Lead with
-- these at session start — a failed extinguisher sitting open is what
-- the property manager will ask about. This is not the official AHJ log.
CREATE VIEW IF NOT EXISTS device_fails_open AS
SELECT
  d.device_id,
  d.building_id,
  b.building_name,
  c.client_id,
  c.client_name,
  d.device_tag,
  d.device_type,
  d.location_note,
  r.result_id,
  r.inspection_id,
  i.inspection_no,
  date(i.scheduled_start)                          AS fail_date,
  r.fail_notes,
  r.photo_count,
  r.report_dc_id,
  r.resolved_at
FROM devices d
JOIN buildings b ON b.building_id = d.building_id
JOIN clients c ON c.client_id = b.client_id
JOIN device_results r ON r.result_id = (
  SELECT r2.result_id FROM device_results r2
  WHERE r2.device_id = d.device_id
  ORDER BY r2.result_id DESC LIMIT 1
)
JOIN inspections i ON i.inspection_id = r.inspection_id
WHERE d.is_active = 1
  AND r.result = 'fail'
  AND r.resolved_at IS NULL
ORDER BY i.scheduled_start DESC, b.building_name, d.device_tag;

-- Active devices on a scheduled or just-completed inspection that have no
-- Device Inspection submission yet. "3 of 12 devices not submitted."
CREATE VIEW IF NOT EXISTS devices_missing_this_visit AS
SELECT
  i.inspection_id,
  i.inspection_no,
  i.status,
  date(i.scheduled_start)                          AS inspection_date,
  b.building_id,
  b.building_name,
  d.device_id,
  d.device_tag,
  d.device_type,
  d.location_note,
  d.last_result
FROM inspections i
JOIN buildings b ON b.building_id = i.building_id
JOIN devices d ON d.building_id = i.building_id AND d.is_active = 1
WHERE i.status IN ('scheduled', 'completed')
  AND NOT EXISTS (
    SELECT 1 FROM device_results r
    WHERE r.inspection_id = i.inspection_id
      AND (r.device_id = d.device_id OR lower(r.device_tag) = lower(d.device_tag))
  )
ORDER BY i.scheduled_start, b.building_name, d.device_tag;

-- Completed inspections whose photo results are on file but have not yet
-- been turned into a client pack. "Export Riverside Plaza" reads this,
-- calls form_export + shift_status, then sets exported_at.
CREATE VIEW IF NOT EXISTS reports_to_export AS
SELECT
  i.inspection_id,
  i.inspection_no,
  i.status,
  date(i.scheduled_start)                          AS inspection_date,
  i.scheduled_start,
  c.client_id,
  c.client_name,
  c.billing_email,
  b.building_id,
  b.building_name,
  b.address || COALESCE(', ' || b.city, '')
            || COALESCE(', ' || b.region, '')
            || COALESCE(' ' || b.postcode, '')     AS street_address,
  i.zensched_event_id,
  i.zensched_shift_id,
  i.checked_in_at,
  i.checked_out_at,
  i.gps_verified,
  i.checkin_distance_m,
  i.exported_at,
  k.technician_name,
  (SELECT COUNT(*) FROM device_results r WHERE r.inspection_id = i.inspection_id) AS result_count,
  (SELECT COUNT(*) FROM device_results r WHERE r.inspection_id = i.inspection_id AND r.result = 'fail') AS fail_count
FROM inspections i
JOIN clients c ON c.client_id = i.client_id
JOIN buildings b ON b.building_id = i.building_id
LEFT JOIN technicians k ON k.technician_id = i.technician_id
WHERE i.status = 'completed'
  AND EXISTS (SELECT 1 FROM device_results r WHERE r.inspection_id = i.inspection_id)
  AND i.exported_at IS NULL
ORDER BY i.scheduled_start;

-- Uninvoiced billable work grouped by client, with the billing contact and
-- terms. Completed visits bill their full fees; missed visits bill travel
-- only; cancellations bill other_fee only (see billable_inspections).
CREATE VIEW IF NOT EXISTS receivables_by_client AS
SELECT
  c.client_id,
  c.client_name,
  c.client_type,
  c.contact_name,
  c.billing_email,
  c.payment_terms_days,
  COUNT(b.inspection_id)                           AS inspection_count,
  SUM(CASE WHEN b.status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
  SUM(CASE WHEN b.status = 'missed' THEN 1 ELSE 0 END)    AS missed_count,
  SUM(b.billable_total)                            AS total_billable,
  MIN(b.inspection_date)                           AS first_date,
  MAX(b.inspection_date)                           AS last_date
FROM billable_inspections b
JOIN clients c ON c.client_id = b.client_id
WHERE b.invoiced = 0
  AND b.status IN ('completed', 'missed', 'cancelled')
  AND b.billable_total > 0
GROUP BY c.client_id
ORDER BY total_billable DESC;

-- Unpaid invoices with aging. days_past_due is negative while not yet due.
--   current : not yet due
--   30      : 1-30 days past due
--   60      : 31-60 days past due
--   90+     : more than 60 days past due (chase now)
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  inv.invoice_id,
  inv.invoice_number,
  c.client_id,
  c.client_name,
  c.client_type,
  c.contact_name,
  c.billing_email,
  c.payment_terms_days,
  inv.invoice_date,
  inv.due_date,
  inv.sent_date,
  inv.total_amount,
  CAST(julianday(date('now', 'localtime')) - julianday(inv.due_date) AS INTEGER) AS days_past_due,
  CASE
    WHEN julianday(date('now', 'localtime')) - julianday(inv.due_date) <= 0  THEN 'current'
    WHEN julianday(date('now', 'localtime')) - julianday(inv.due_date) <= 30 THEN '30'
    WHEN julianday(date('now', 'localtime')) - julianday(inv.due_date) <= 60 THEN '60'
    ELSE '90+'
  END                                              AS aging_bucket,
  CASE WHEN inv.due_date < date('now', 'localtime') THEN 1 ELSE 0 END AS overdue
FROM invoices inv
JOIN clients c ON c.client_id = inv.client_id
WHERE inv.paid = 0
ORDER BY inv.due_date;
