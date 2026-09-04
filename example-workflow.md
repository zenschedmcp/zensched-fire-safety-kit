# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

The business is **Apex Fire Protection**, a solo shop (Luis Ortega) in Dallas, Central time (`-05:00` in September). IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: the lockbox code, Luis's licence number. ZenSched sees `Riverside Plaza`, a street address, and a per-device Device Inspection. Nothing is filed with an AHJ.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Fire Safety Co, timezone_offset = -05:00,
    default_tech_id = NULL, default_visit_minutes = 90,
    default_travel_buffer_minutes = 20, invoice_due_days = 30, invoice_prefix = INV,
    inspection_form_id = NULL, event_window_days = 60
sqlite_query:   SELECT * FROM device_fails_open;     → (none)
sqlite_query:   SELECT * FROM reports_to_export;     → (none)
sqlite_query:   SELECT * FROM inspections_today;     → (none)
```

## "We're Apex Fire Protection in Dallas, Central time. It's just me, Luis Ortega, luis@apexfire.example, 214-555-0100. Set me up."

```
sqlite_execute: UPDATE settings SET value = 'Apex Fire Protection' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
```

Agent (first metered call this session, rule 11):

> Saved. Since you're the tech on the phone, I need to invite you to ZenSched as a worker so your visits show up in the app; that's a one-time $0.25. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
worker_invite:
  email: "luis@apexfire.example"
  first_name: "Luis"
  last_name: "Ortega"
  idempotency_key: "worker-luis@apexfire.example"
  → worker_id: 601, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO technicians (technician_name, email, phone, zensched_worker_id, is_owner)
  VALUES ('Luis Ortega', 'luis@apexfire.example', '214-555-0100', 601, 1);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '1' WHERE key = 'default_tech_id';
```

> You're invited; install the app from the email. Your visits will land on your own phone. Next, the Device Inspection: it's free to create and every unit comes back with the tag, type, Pass / Fail / Serviced, up to two tag photos, and fail notes when it fails. No signature pad on it, on purpose — this is not an AHJ filing. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Device Inspection"
  idempotency_key: "form-device-inspection"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Device", "identifier": "device", "text": "One submission per device. Type the tag exactly as it is on the unit. Do not write lockbox codes, fire-panel codes, or licence numbers here. Photos are stored as uploaded — ZenSched does not burn a date, time, or GPS stamp onto the image. This form is not an AHJ filing."},
  {"type": "text", "label": "Device tag", "identifier": "device_tag", "required": true, "placeholder": "FE-12"},
  {"type": "select", "label": "Type", "identifier": "device_type", "required": true,
   "options": ["Extinguisher", "Light", "Exit", "Hose"]},
  {"type": "select", "label": "Result", "identifier": "result", "required": true,
   "options": ["Pass", "Fail", "Serviced"]},
  {"type": "photo", "label": "Tag photo", "identifier": "tag_photo", "required": true, "max_images": 2},
  {"type": "textarea", "label": "Fail notes", "identifier": "fail_notes",
   "show_if": {"field": "result", "op": "equals", "value": "fail", "action": "show"}}
]
```

```
  → form_id: 401, fields: [ ...6 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '401' WHERE key = 'inspection_form_id';
```

> Device Inspection form created. I'll attach it to every building automatically. One thing to know: you submit it once per device, and reading a photo submission later costs $0.15 each, once ever.

## "Add Meridian Property Group, they pay $185 a visit net 30. Then add Riverside Plaza, 400 Oak Street, Dallas TX 75201, monthly starting Thursday 10 September 2026 at 9, lockbox 4411. Devices: FE-01 lobby 10 lb ABC extinguisher, EL-A stair A emergency light, EX-2 second-floor exit, HR-B basement hose."

```
sqlite_execute:
  INSERT INTO clients (client_name, client_type, billing_email, payment_terms_days, default_visit_fee)
  VALUES ('Meridian Property Group', 'property_manager', 'ap@meridian.example', 30, 185.00);
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO buildings (client_id, building_name, address, city, region, postcode, country,
                         street_name, building_label, access_notes, visit_frequency,
                         next_visit_date, preferred_start)
  VALUES (1, 'Riverside Plaza', '400 Oak Street', 'Dallas', 'TX', '75201', 'US',
          '400 Oak Street', 'Riverside Plaza', 'Lockbox 4411, panel in riser A.',
          'monthly', '2026-09-10', '09:00');
  → lastInsertRowid = 1

sqlite_execute: INSERT INTO devices (building_id, device_tag, device_type, location_note, size_note)
                VALUES (1, 'FE-01', 'extinguisher', 'Lobby', '10 lb ABC');
sqlite_execute: INSERT INTO devices (building_id, device_tag, device_type, location_note)
                VALUES (1, 'EL-A', 'light', 'Stair A');
sqlite_execute: INSERT INTO devices (building_id, device_tag, device_type, location_note)
                VALUES (1, 'EX-2', 'exit', 'Second floor');
sqlite_execute: INSERT INTO devices (building_id, device_tag, device_type, location_note)
                VALUES (1, 'HR-B', 'hose', 'Basement');
```

Nothing about the lockbox is in a ZenSched field.

Agent (metered geocode, rule 11):

> Creating Riverside Plaza on ZenSched costs $0.03 for geocoding. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Riverside Plaza"
  street_address: "400 Oak Street, Dallas, TX 75201"
  checkin_radius_m: 150
  idempotency_key: "loc-building-1"
  → location_id: 9201, lat: 32.7801, lng: -96.8000, pin_quality: "street",
    billing: { meter: "geocode", units: 1, price: 0.03 }

event_create:
  location_id: 9201
  title: "Fire safety - Riverside Plaza"
  start_date: "2026-09-10"
  end_date:   "2026-11-08"          ← start + 59 days (60-day cap)
  idempotency_key: "event-building-1-20260910"
  → event_id: 8101

form_assign:
  form_id: 401
  event_id: 8101
  idempotency_key: "assign-device-inspection-8101"
  → status: "assigned"

sqlite_execute:
  UPDATE buildings SET zensched_location_id = 9201, zensched_event_id = 8101, event_valid_until = '2026-11-08'
  WHERE building_id = 1;
```

> Added Meridian Property Group ($185/visit, net 30) and Riverside Plaza, 400 Oak Street, monthly from Thu Sep 10 at 09:00. Four devices: FE-01 extinguisher, EL-A light, EX-2 exit, HR-B hose. The lockbox code is on your computer only; ZenSched knows the building as "Riverside Plaza". Event runs through Nov 8.

## "Schedule this week."

```
sqlite_query: SELECT * FROM buildings_due;
  → building 1 | Riverside Plaza | Meridian | monthly | 2026-09-10 | 09:00 | 90 min
               | event 8101 | event_needs_roll 0 | worker 601 Luis | device_count 4
               | start_iso 2026-09-10T09:00:00-05:00 | end_iso 2026-09-10T10:30:00-05:00
               | shift-building-1-20260910

sqlite_execute:
  INSERT INTO inspections (client_id, building_id, scheduled_start, status)
  VALUES (1, 1, '2026-09-10T09:00', 'scheduled');
  → lastInsertRowid = 1
  (trigger fills: inspection_no INSP-2026-0001, duration 90, technician_id 1, visit_fee 185, travel_fee 0)

shift_create:
  event_id: 8101
  worker_id: 601
  start: "2026-09-10T09:00:00-05:00"
  end:   "2026-09-10T10:30:00-05:00"
  idempotency_key: "shift-building-1-20260910"
  → shift_id: 99001, status: "scheduled", forms_installed: [401]

sqlite_execute:
  UPDATE inspections SET zensched_event_id = 8101, zensched_shift_id = 99001 WHERE inspection_id = 1;
```

> Scheduled **INSP-2026-0001**: Thu Sep 10 09:00–10:30, Riverside Plaza, 4 devices, $185. It's on your phone with the Device Inspection attached. Submit the form once per device.

## The tech does the work

Thursday 8:54, at 400 Oak Street: Luis taps **Check in** (GPS: 14 m from the pin, verified, $0.10). Walks the four units.

- FE-01: Type Extinguisher, Result **Fail**, Fail notes "Gauge in the red; needs recharge.", two tag photos. Submit.
- EL-A: Type Light, Result Pass, one tag photo. Submit.
- EX-2: Type Exit, Result Pass, one tag photo. Submit.
- HR-B: Type Hose, Result Serviced, notes none, one tag photo. Submit.

**Check out** 10:22.

## "Close out today."

```
shift_list:
  date_from: "2026-09-10"
  date_to:   "2026-09-10"
  status:    "checked_out"
  → shifts: [{ shift_id: 99001, event_id: 8101, worker_id: 601, date: "2026-09-10", status: "checked_out" }]

shift_status: shift_id 99001
  → actual_in "2026-09-10T08:54:00-05:00", actual_out "2026-09-10T10:22:00-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 14 },
               { type: "out", gps_verified: true, distance_from_site_m: 9 } ]
```

Agent (metered read, rule 11):

> There are 4 Device Inspections to pull, all with photos, so about $0.60. I'll read them once and keep the results locally. OK?

Owner: *"go"*

```
form_export:
  form_id: 401
  since: "2026-09-10"
  until: "2026-09-10"
  format: "json"
  → row_count: 4, rows: [
      { submission_id: 4401, worker_id: 601, event_id: 8101, submitted_at: "2026-09-10 09:12:00",
        data: { device_tag: "FE-01", device_type: "extinguisher", result: "fail",
                fail_notes: "Gauge in the red; needs recharge." },
        media: [ { field: "tag_photo", ... }, { field: "tag_photo", ... } ] },
      { submission_id: 4402, ..., data: { device_tag: "EL-A", device_type: "light", result: "pass" } },
      { submission_id: 4403, ..., data: { device_tag: "EX-2", device_type: "exit", result: "pass" } },
      { submission_id: 4404, ..., data: { device_tag: "HR-B", device_type: "hose", result: "serviced" } }
    ]
    billing: { meter: "form_media", units: 4, price: 0.60 }

sqlite_execute:
  INSERT INTO device_results (inspection_id, device_tag, device_type, result, fail_notes, photo_count, report_dc_id)
  VALUES (1, 'FE-01', 'extinguisher', 'fail', 'Gauge in the red; needs recharge.', 2, 4401);
  (trigger matches device_id 1, sets last_result = fail)

sqlite_execute:
  INSERT INTO device_results (inspection_id, device_tag, device_type, result, photo_count, report_dc_id)
  VALUES (1, 'EL-A', 'light', 'pass', 1, 4402);
sqlite_execute:
  INSERT INTO device_results (inspection_id, device_tag, device_type, result, photo_count, report_dc_id)
  VALUES (1, 'EX-2', 'exit', 'pass', 1, 4403);
sqlite_execute:
  INSERT INTO device_results (inspection_id, device_tag, device_type, result, photo_count, report_dc_id)
  VALUES (1, 'HR-B', 'hose', 'serviced', 1, 4404);

sqlite_execute:
  UPDATE inspections SET status = 'completed',
    checked_in_at = '2026-09-10T08:54:00-05:00', checked_out_at = '2026-09-10T10:22:00-05:00',
    gps_verified = 1, checkin_distance_m = 14
  WHERE inspection_id = 1;
  (trigger advances Riverside next_visit_date to 2026-10-10, last_visit_date 2026-09-10)

sqlite_query: SELECT * FROM inspection_device_summary WHERE inspection_id = 1;
  → expected 4 | results 4 | pass 2 | fail 1 | serviced 1 | missing 0
sqlite_query: SELECT * FROM device_fails_open;
  → FE-01 extinguisher | Riverside Plaza | INSP-2026-0001 | Gauge in the red; needs recharge.
```

> Closed **INSP-2026-0001**: Riverside Plaza, GPS-verified 08:54–10:22.
>
> **One fail — FE-01 (lobby extinguisher):** *"Gauge in the red; needs recharge."* EL-A and EX-2 passed; HR-B was serviced. 4 of 4 devices submitted. $185 now receivable from Meridian, net 30. Next monthly visit is Oct 10. This is on `reports_to_export` until you ask me to export the pack. It is not an AHJ filing.

## "Export Riverside Plaza."

```
sqlite_query: SELECT * FROM reports_to_export;
  → INSP-2026-0001 | Riverside Plaza | fail_count 1 | result_count 4

form_export: form_id 401, event_id 8101, since "2026-09-10", until "2026-09-10", format "json"
  → (replay; already billed; photo URLs)

sqlite_execute: UPDATE inspections SET exported_at = datetime('now', 'localtime') WHERE inspection_id = 1;
```

The agent writes a plain-text client pack: inspection number, street, GPS in/out, one line per device with photo URLs, and a line that this is **not** an AHJ filing and that photos have **no burned-in GPS stamp**.

## "Invoice Meridian."

```
sqlite_query: SELECT * FROM receivables_by_client;
  → Meridian Property Group | 1 completed | $185.00 | 2026-09-10

sqlite_execute:
  INSERT INTO invoices (client_id, invoice_date, due_date, total_amount, line_items)
  SELECT b.client_id, date('now', 'localtime'),
         date('now', 'localtime', '+' || (SELECT payment_terms_days FROM clients WHERE client_id = 1) || ' days'),
         SUM(b.billable_total),
         json_group_array(json_object('inspection_no', b.inspection_no, 'date', b.inspection_date,
                                      'status', b.status, 'visit_fee', b.visit_fee, 'billable', b.billable_total))
  FROM billable_inspections b WHERE b.invoiced = 0 AND b.client_id = 1 AND b.billable_total > 0
  GROUP BY b.client_id;

sqlite_execute: UPDATE inspections SET invoiced = 1 WHERE invoiced = 0 AND client_id = 1 AND status IN ('completed', 'missed', 'cancelled');
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-10 | 2026-10-10 | 185.00
```

> Here's the Meridian invoice, ready to paste into an email.
>
> ```
> Apex Fire Protection
> Invoice INV-2026-0001
> To: Meridian Property Group (ap@meridian.example)
> Date: Sep 10, 2026    Due: Oct 10, 2026
>
>   INSP-2026-0001   Sep 10   Riverside Plaza   $185.00
>
> Total due: $185.00
> Visit GPS-verified at 400 Oak Street. This invoice is not an AHJ certificate.
> ```
>
> Say "sent" when it's out.

## Eight weeks later: "Schedule this week."

```
sqlite_query: SELECT * FROM buildings_due;
  → 2026-11-10 | Riverside Plaza | evt 8101 | event_valid_until 2026-11-08 | event_needs_roll 1 | ...

event_create:
  location_id: 9201
  title: "Fire safety - Riverside Plaza"
  start_date: "2026-11-10"
  end_date:   "2027-01-08"
  idempotency_key: "event-building-1-20261110"
  → event_id: 8201

form_assign: form_id 401, event_id 8201, idempotency_key "assign-device-inspection-8201"
sqlite_execute: UPDATE buildings SET zensched_event_id = 8201, event_valid_until = '2027-01-08' WHERE building_id = 1;

INSERT INTO inspections ... scheduled_start '2026-11-10T09:00'
shift_create: event_id 8201, key "shift-building-1-20261110"
```

> Scheduled the week. Riverside's ZenSched event expired Nov 8, so I renewed it through Jan 8 and attached the Device Inspection again. Nothing changes for you on the phone except the new date.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Meridian's billing email, terms, visit fee | SQLite | Billing; ZenSched does not model payers |
| Riverside lockbox / fire-panel code | SQLite **only** | Privacy; never sent to ZenSched |
| Device inventory (FE-01, EL-A, EX-2, HR-B), location notes, last result | SQLite | Coverage and open-fail queries |
| Luis's licence number | SQLite **only** | Privacy |
| "Riverside Plaza" and the street address, GPS pin | ZenSched (ID in `buildings`) | Needed for geofenced check-in |
| The building's current ≤60-day event and its end date | ZenSched (ID + `event_valid_until` in `buildings`) | Shifts hang off events; renewed by the agent |
| The Device Inspection form | ZenSched (ID in `settings`) | Installed on the phone per shift |
| The Thursday shift | ZenSched only | Live schedule |
| GPS punches | ZenSched only; stamps copied to `inspections` | Verified record |
| Four Device Inspection submissions with photos | ZenSched (originals); tag / type / result / notes / `report_dc_id` in `device_results` | Read once (metered), then answered from SQLite |
| One invoice, open fail on FE-01 | SQLite | Money and statutory follow-up — not an AHJ filing |
