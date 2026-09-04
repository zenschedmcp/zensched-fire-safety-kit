# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "This is not an AHJ e-file tool" section of `README.md`. Short version: this kit puts each building visit on your phone, GPS-stamps arrival, and collects a per-device photo inspection; it does not file with a fire marshal or The Compliance Engine, does not generate a branded PDF, and does not burn a GPS stamp onto photos. The Device Inspection is **not** the official NFPA 10 / BS 5306-3 / AS 1851 service record (and not a replacement for the tag on the cylinder). Lockbox codes and licence numbers stay on your computer; ZenSched only ever sees a building label (`Riverside Plaza`), an address, and the Device Inspection form.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\firesafe-ops` (Windows) or `/Users/yourname/firesafe-ops` (Mac). Note the full path. It will hold lockbox codes and licence numbers, so keep it on an encrypted, backed-up disk.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\firesafe-ops\\firesafe-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Fire Safety Co". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my firesafe-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> We're Apex Fire Protection in Dallas, Central time. It's just me, Luis Ortega, luis@example.com. Set me up.

The AI saves your settings, invites **you** to ZenSched as a worker ($0.25, once; you are the tech on the phone), and calls `form_create` once (free) to build the Device Inspection you fill in at each unit: device tag, type (Extinguisher / Light / Exit / Hose), result (Pass / Fail / Serviced), up to two tag photos, and fail notes when the result is Fail. No signature pad. It stores the form id so every building visit gets it. Install the app from the invitation email ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)).

Optional but recommended: "Allow check-in 20 minutes early and set the radius to 200 m." Techs arrive early and often park far from a campus entrance. The radius is a **policy** setting, not per building.

## 6. Add your first client, building, and devices

> Add Meridian Property Group, they pay $185 a visit net 30. Then add Riverside Plaza, 400 Oak Street, Dallas TX 75201, monthly starting Thursday 10 September 2026 at 9, lockbox 4411. Devices: FE-01 lobby 10 lb ABC extinguisher, EL-A stair A emergency light, EX-2 second-floor exit, HR-B basement hose.

Behind the scenes the AI inserts the client and the building (lockbox local only), inserts the four devices, calls `location_create` for "Riverside Plaza" (geocode, $0.03, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` titled `Fire safety - Riverside Plaza`, attaches the Device Inspection with `form_assign`, and saves the IDs. You just see a confirmation.

## 7. Schedule the week

> Schedule this week.

The AI reads `buildings_due`, creates one inspection (`INSP-2026-0001`) and one shift per building, and summarizes. You get a push notification. At the door, **Check in** (GPS-verified). Walk the devices. Open **Device Inspection** once per unit: type the tag, pick the type, pick Pass / Fail / Serviced, take up to two tag photos, add fail notes if it failed. Submit. **Check out**.

Photos are stored as you took them. ZenSched does **not** burn a date, time, or GPS stamp onto the image; the punch record is the location/time proof.

## 8. Close out and export

> Close out today.

The AI pulls your GPS-verified arrival and departure (free), reads the Device Inspection submissions (metered, so it tells you the cost first — about $0.15 per device with photos), updates the visit, advances the building's next date, and leads with anything marked Fail.

> Export Riverside Plaza.

A plain-text client pack: GPS in/out, one line per device (tag, type, result, fail notes, photo links), coverage. You paste it into an email to the property manager. This is **not** an AHJ filing, **not** the official NFPA 10 / BS 5306-3 / AS 1851 record, and not a branded PDF.

## 9. Money

> Invoice Meridian Property Group.

A plain-text invoice under their terms with one line per building visit.

> Who owes me money?

Open invoices aged current / 30 / 60 / 90+ days past due.

> Meridian paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the AHJ / PDF / photo-stamp / privacy boundaries, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
