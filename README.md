# ZenSched Fire-Safety Reference Kit

A copy-pasteable setup for a small fire-extinguisher and emergency-light shop (solo, or a 2–6 tech firm) that wants an AI assistant to run contracted building lists, a per-building device inventory (extinguishers, emergency lights, exit signs, hose reels), GPS-verified building visits, a per-device inspection form, local statutory records, and invoicing. ZenSched handles the live schedule, the tech's phone app, GPS check-ins at the building, and the Device Inspection form. A small local database on your computer holds your clients, buildings, devices, technicians, inspection summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule this week", "add Riverside Plaza", "what failed at Oak Street", "export Riverside", "invoice Meridian") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## This is not an AHJ e-file tool — read this first

**What this kit is:** a way for a small fire shop to get every contracted building onto the tech's phone, prove GPS-verified arrival, record a Device Inspection (tag, type, Pass / Fail / Serviced, tag photo) once per device, and turn those records into a local statutory log, a client pack, invoices, and a list of open fails, with an AI assistant doing the clerical work.

**What it is not:**

- **It is not an AHJ e-file tool.** It does not submit to a fire marshal, a building department, The Compliance Engine, Brycer, NFIRS, or any authority-having-jurisdiction portal. It does not produce a compliance certificate. `device_results` plus a `form_export` give you the tags, results, photos, and GPS-verified times; you (or the client) paste that into *your* report or email and file however you file today.
- **It is not a branded PDF inspection report generator.** Tools such as The Compliance Engine, Inspect Point, and similar products render a formatted report and often file it for you. This kit does not. The Device Inspection on the phone is an operational photo form; the "export" is plain text plus photo links.
- **It does not watermark photos.** ZenSched records the GPS punch coordinates and the upload time server-side, but the exported image is **not** stamped with the date, time, and coordinates. The punch record is your corroboration that the tech was at the pin when the photos were taken. If an AHJ later wants a *readable* stamp on the image itself, shoot with your phone camera's timestamp / GPS overlay turned on and upload *that* image.
- **The Device Inspection has no signature field.** On ZenSched a signature field replaces the Submit button. Submitting the form is just submitting the form; it is not a signed legal document.

If any of that is a deal-breaker, this kit is not for you. If you want a phone schedule with GPS proof of arrival, a per-device photo record, and receivables you can actually chase, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (one per building, kept forever; the check-in radius is a **policy** setting)
- Workers (you, in solo mode; you plus your techs, each with the mobile app)
- Events (one "Fire safety" job per building, renewed every 60 days)
- Shifts (one per building visit, 90 minutes by default, with a push notification to the tech)
- GPS punches (check-in / check-out with distance-from-the-pin verification)
- The Device Inspection form (tag, type, result, tag photo, fail notes) and every per-device submission with its photos

**Local SQLite database (`firesafe-ops.db`, on your computer):**

- Clients: property managers, building owners, facility firms, HOAs, with payment terms and default visit fees
- Buildings: every contracted site, with its ZenSched location and current 60-day event, cadence (monthly / quarterly / annual / on-demand), and access notes (lockbox, fire panel) — **access notes never leave your computer**
- Devices: tag, type (extinguisher / light / exit / hose), location note, last result
- Technicians, including licence numbers that **never leave your computer**
- Inspections: one row per building visit, with the ZenSched shift id, GPS arrival stamps, and fees
- Device results copied from each form submission; invoices with aging
- Your settings (timezone, default tech, default visit length, invoice terms and prefix, Device Inspection form id)

**Never duplicated:** the live schedule, punches, and photos stay in ZenSched. The local database stores *references* to them plus the few facts you need to answer "what failed at Riverside", "export Oak Street", and "who owes me" without paying to re-read records.

### Privacy note

Lockbox codes, fire-panel codes, after-hours contacts, and technician licence numbers live only in the local database: `buildings.access_notes` and `technicians.license_no`. `SKILL.md` forbids the AI from putting any of them into any ZenSched field, including location names, event titles, notes, and cancellation reasons (techs see those). Location name and event title are the building name — `Fire safety - Riverside Plaza` — never a code. The Device Inspection form itself tells the tech not to write codes in it. You are still responsible for your own privacy obligations (the local database, your email, your phone); this kit narrows what a third party sees, it does not make you compliant by itself.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `form_export`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `firesafe-ops.db` on your computer.

When you say "schedule this week," the AI reads who is due from the local database (`next_visit_date` in the next 7 days), creates one inspection and one shift per building on ZenSched, and tells you what it did. Your tech sees the visits in the app, checks in at the building (GPS-verified), walks the devices, fills in the Device Inspection **once per device** (tag, type, Pass / Fail / Serviced, tag photo), and checks out. Later you say "close out today" and the AI pulls the completed shifts and the per-device submissions, saves the results locally, advances each building's next date (monthly +1 month, quarterly +90 days, annual +1 year), and leads with anything marked Fail. "Export Riverside Plaza" writes the client pack (GPS times + photo links). "Invoice Meridian" produces a plain-text invoice under their terms. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical building visit costs **$0.20 in GPS** (in + out) plus **$0.15 per device** to read a photo Device Inspection (once ever; replays are free). A 4-device building is about **$0.80**; a 12-device building is about **$2.00**. Geocoding a new building is $0.03 once. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\firesafe-ops`
- Mac: `/Users/yourname/firesafe-ops`

The database file will be created automatically inside this folder the first time the AI uses it. This folder will contain lockbox codes and licence numbers; keep it on an encrypted, backed-up disk, not in a shared folder.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\firesafe-ops.db` (Windows) or `/firesafe-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "firesafe-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/firesafe-ops/firesafe-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\firesafe-ops\\firesafe-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Fire Safety Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my firesafe-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run 58 statements and confirm the tables exist. The `firesafe-ops.db` file now exists in your folder with default settings (90-minute visits, net 30, Central `-05:00`) you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 firesafe-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> We're Apex Fire Protection in Dallas, Central time. It's just me, Luis Ortega, luis@example.com. Set me up.

It writes those to the `settings` table, **invites you to ZenSched as a worker** (you are the tech on the phone; $0.25, one time), creates the Device Inspection form on ZenSched (free), and saves the form id so every building visit gets it automatically. Then say "add my tech Maya Chen, maya@example.com" for each extra tech you dispatch.

**Check-in radius.** ZenSched enforces the radius through the account's policy, not per building, and with geofencing on it raises anything under 100 m to about 91 m (300 ft). For campuses, loading docks, and multi-building sites where you park a long way from the entrance, ask the AI to "set the check-in radius to 200 m" (`policy_update`), or to move the pin onto the entrance (`location_update`, free; the building keeps it). Never ask it to "widen the radius on that location" — that field is informational only. `remote_checkin` turns GPS verification off for every visit and should be a last resort, because it also turns off the proof.

**Forgotten check-outs.** Ask the AI to "remind me to check out 15 minutes after the shift ends" (`checkout_reminder_min_after`).

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03; skipped once a building is pinned), inviting a worker ($0.25, including yourself), each GPS-verified check-in or check-out ($0.10), and reading a Device Inspection ($0.05, or $0.15 when it has photos; each record is billed once, ever; replays are free). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A 4-device visit at a new building costs $0.03 + $0.20 + $0.60 = **~$0.83**; a repeat visit is **~$0.80**. A 12-device monthly building is about **$2.00** per visit in form reads plus GPS. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add Meridian Property Group, they pay $185 a visit net 30. Then add Riverside Plaza, 400 Oak Street, Dallas TX 75201, monthly starting Thursday, lockbox 4411. Devices: FE-01 lobby extinguisher, EL-A stair light, EX-2 second-floor exit, HR-B basement hose."
- "Schedule this week."
- "What's today?" / "What's this week?"
- "Close out today."
- "What failed at Riverside?"
- "Export Riverside Plaza."
- "The Thursday walk moved to 1." / "Cancel Cedar Court; they owe a $40 wasted-journey fee."
- "Invoice Meridian." / "Who owes me money?"
- "Meridian paid INV-2026-0001."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Invoice Meridian" records the invoice in your database (number, date, due date under that client's terms, total, which inspections with their fee breakdown) and the AI writes out a plain-text invoice you can paste into an email, with a line per building visit. It does **not** generate a PDF, submit it for you, or collect payment, and it does not add VAT or sales tax. It is not an AHJ certificate. When the client pays, tell the AI ("Meridian paid INV-2026-0001") and it marks it paid. "Who owes me money" ages what is open into current / 30 / 60 / 90+ days past due.

## Mobile app for technicians

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

In solo mode you invite yourself; the email arrives at your own address, you install the app, and your building visits appear as they are scheduled. Each one shows the address and time; you check in on arrival (GPS-verified), walk the devices, fill in the Device Inspection once per unit (tag, type, result, tag photo, fail notes if it failed), and check out. There is no signature step; you submit each device yourself.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `firesafe-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, or daylight saving changed | "Set my timezone offset to -05:00 in settings" (use your own offset) |
| Shift creation fails for dates a couple of months out | The building's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Visit not on my phone | Booked locally but the ZenSched shift was never created (`needs_shift = 1`) | "Put today's inspections on my phone"; the AI finishes the schedule steps |
| Check-in not GPS-verified at a campus / loading dock | You parked outside the policy radius, or the pin is on the road | "Set the check-in radius to 200 m" (`policy_update`), or "move the pin to the main entrance" (`location_update`, free). Do not ask to widen the radius "on that location" |
| Forgot to check out | Shift still `checked_in` | Tell the AI the real time; ask for a 15-minute check-out reminder |
| Device Inspection not on the phone | Form not assigned to that building's event before the shift was created | "Attach the Device Inspection to Riverside" (`form_assign`), then cancel and recreate the shift |
| "Fail notes" shows even when the result is Pass | Conditional fields are web-only on ZenSched | Harmless; leave it blank |
| Photos have no date/GPS printed on them | Working as intended | ZenSched does not burn a stamp onto the image. The punch record holds the GPS/time. Use a camera overlay if you need pixels stamped |
| AI refuses to put the lockbox code on ZenSched | Working as intended | Access codes stay on your computer |
| Typed tag does not match the inventory | Tech typed `fe-01` vs `FE-01`, or a new unit | Matching is case-insensitive. If it is a new unit, tell the AI to add it |
| Inspection numbers look like invoices | You numbered an inspection `INV-` | Inspections are `INSP-YYYY-0001`; invoices are `INV-YYYY-0001`. Leave `inspection_no` NULL and the trigger assigns `INSP-` |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, form submissions); SQLite is authoritative for clients, buildings (the places), the device inventory, roster, inspections, device results, and billing; each side stores only the other's IDs, plus a per-visit / per-device summary and the GPS stamps cached locally because submission reads are metered. The privacy boundary is enforced by data placement (access-note and licence columns exist only locally) and by `SKILL.md` rules 1–3; there is no technical control stopping a misbehaving agent, so review the rules if you swap models.

**Data model decisions.**

- **Buildings are the places, with a 60-day event roll.** One ZenSched **location** per building, permanent, stored on `buildings.zensched_location_id`. Created with `location_create(name=<building_label>, street_address=..., checkin_radius_m=150, idempotency_key="loc-building-{building_id}")`. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft. **Events are capped at 60 days**, so each building holds its *current* event in `buildings.zensched_event_id` and its last covered date in `buildings.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Fire safety - <label>", start_date, end_date=start+59 days, idempotency_key="event-building-{building_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign` on it, and updates the row. `buildings_due` / `inspections_upcoming` expose `event_needs_roll`; `events_expiring` lists buildings due for renewal within 14 days. Shifts already created on the old event remain valid.
- **One shift per building visit, not per device.** `inspections` is the visit table. The tech submits the Device Inspection form once per device during that shift; `device_results` is one row per submission. Matching is `lower(device_tag)` against `devices` on that building; unknown tags keep `device_id` NULL so the owner can add the unit later.
- **Cadence lives on the building.** `visit_frequency` is `monthly` / `quarterly` / `annual` / `on-demand`. Completing an inspection fires `advance_next_visit_on_complete`: monthly +1 month, **quarterly +90 days** (not +3 months), annual +1 year, on-demand clears `next_visit_date`. `buildings_due` is the next 7 days from `next_visit_date`, excluding buildings that already have a scheduled or completed inspection on that date.
- **`inspection_no`** is assigned by trigger as `INSP-{YYYY of scheduled_start}-{inspection_id:04d}` when left NULL. **Do not use `INV-`** — that prefix is `invoices.invoice_number`.
- **`scheduled_start` is local wall-clock time without an offset** (`2026-09-10T09:00`, `CHECK`-constrained to reject a trailing offset or `Z`). Views emit `start_iso` / `end_iso` by appending `settings.timezone_offset`. Day-based views use `date('now', 'localtime')` because the SQLite MCP server runs on the owner's computer.
- **`billable_total` is computed in a view, not stored.** Fee columns are snapshots filled by trigger. `billable_inspections`: `completed` → visit + travel + other; `missed` → travel only; `cancelled` → `other_fee` only; `scheduled` → 0.
- **No signature field on the form.** ZenSched replaces the Submit button with the signature pad when a form has a `signature` field. `tag_photo` is a required `photo` field (`max_images: 2`); a submission with photos bills $0.15 instead of $0.05, **per device**.
- **Open fails.** `device_fails_open` is the latest `device_results` row per device where `result = 'fail'` and `resolved_at` is NULL. Inserting a later `pass` or `serviced` for that `device_id` sets `resolved_at` on the prior fails and stamps `devices.last_result`.
- **`exported_at`** gates `reports_to_export`. The agent sets it after writing the client pack so the same visit does not keep appearing at session start. The pack is not an AHJ filing.
- `inspections.zensched_shift_id`, `technicians.zensched_worker_id`, `device_results.report_dc_id`, and `(building_id, device_tag)` are `UNIQUE`. `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session. Deleting a client cascades to buildings, devices, inspections, results, and invoices; deleting a building is `RESTRICT` while inspections reference it; deleting a technician sets `inspections.technician_id` NULL.

**Device Inspection form.** Created once with `form_create(title, fields_json, idempotency_key="form-device-inspection")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's form validator (`_validate_fields`; 6 fields, well under the 80-field cap). Every field, including the `device` section, carries an explicit `identifier` so submission `data` keys are stable (`device_tag`, `device_type`, `result`, `tag_photo`, `fail_notes`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); every label in this form produces a key shorter than 30 characters (`extinguisher`, `light`, `exit`, `hose`, `pass`, `fail`, `serviced`). One `show_if` references `result` with value `fail`. ZenSched documents conditionals as web-only, so the phone may show "Fail notes" unconditionally. Attaching is `form_assign(form_id, event_id=...)` per building event (and again after every roll).

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-building-{building_id}`
- event: `event-building-{building_id}-{YYYYMMDD window start}`
- shift: `shift-building-{building_id}-{YYYYMMDD}` (a same-day second visit or a tech swap appends `-2`)
- assignment: `assign-device-inspection-{event_id}`
- cancel: `cancel-shift-{shift_id}`
- worker: `worker-{email}`
- form: `form-device-inspection`

ZenSched caches idempotent responses for 24 hours. The views emit `loc_idempotency_key`, `event_idempotency_key`, and `shift_idempotency_key` per row.

**Timestamps.** `shift_create` / `shift_update` take `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-10T09:00:00-05:00`), never `Z`. The views build these strings so the agent does not have to.

**Metered reads.** `form_export` covers a week or a single event in one call and is what "export Riverside Plaza" uses. Both `form_submissions` and `form_export` bill $0.05 per submission ($0.15 with a photo), once per submission ever. A 12-device visit is 12 submissions. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**Check-in policy.** The radius is enforced by `policy_update(0, '{"checkin_radius_m": N}')`, not by `location_create(checkin_radius_m=...)`, which is informational; with geofencing on, values under 100 m are raised to about 91 m. The kit's example sets 200 m / 20 min slack / 15 min check-out reminder for campus sites.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 58 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 8 tables, 11 views, and 10 triggers present; every view on an empty database; `devices (building_id, device_tag)`, `technicians.zensched_worker_id`, `inspections.zensched_shift_id`, and `device_results.report_dc_id` `UNIQUE`; the `number_inspection` trigger (`INSP-YYYY-0001`, explicit number kept); `fill_inspection_defaults` (duration from building then settings, tech from `default_tech_id`, visit fee from building then client, travel from client, else 0, explicit fee kept); `buildings_due` (`start_iso` / `end_iso` with offset for 90- and 60-minute visits, `needs_location`, `event_needs_roll` when `event_valid_until < next_visit_date` or no event, the three idempotency keys, `zensched_event_title` / `zensched_location_name` equal to the building label with no lockbox code, worker id from the building then default tech, 7-day window, inactive / far-out / on-demand-NULL / already-scheduled excluded); `events_expiring`; `inspections_today` / `inspections_upcoming` (`needs_shift` flipping after a shift id is stored, cancelled excluded); `advance_next_visit_on_complete` for monthly (+1 month), **quarterly (+90 days, not +3 months)**, annual (+1 year), and on-demand (NULL), and a second update of an already-completed row not re-advancing; `fill_device_from_result` (case-insensitive tag match, unknown tag leaves `device_id` NULL, `last_result` / `last_inspected_at` stamped, a later pass/serviced sets `resolved_at` on prior fails); `device_fails_open` (latest fail only, empty after resolve, returns after a new fail); `inspection_device_summary` and `devices_missing_this_visit`; `reports_to_export` (drops after `exported_at`); `billable_inspections` for completed (visit + travel), missed (travel only), cancelled (`other_fee` only), and scheduled (0); invoice numbering, `invoices_outstanding` aging buckets `90+` / `60` / `30` / `current` with paid excluded; every `CHECK` (client type, frequency, country, `preferred_start`, device type, result, status, `scheduled_start` format with offset and `Z` rejected, duration range); foreign keys rejecting an unknown client or building, `RESTRICT` on buildings, `SET NULL` on technician delete, and cascade of a client with a building and devices. 156 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
