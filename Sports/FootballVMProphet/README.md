# Football VM Prophet

Free local web dashboard for FIFA World Cup 2026 men.

VM Prophet is a local command center for fixtures, live-status health, upcoming/past match filtering, and manual odds tracking. It is built for **free data first**: no paid API key is required and stale/broken data is shown loudly.

## What it does

- Lists FIFA World Cup 2026 matches from a local fixture JSON file.
- Filters by today, live, upcoming, past, due soon, stage, team, venue, and data status.
- Shows detailed upcoming cards with countdown, venue, source freshness, and watchlist flags.
- Supports manual odds CSV import for 1X2 / over-under / BTTS tracking.
- Calculates implied probability and movement from imported odds snapshots.
- Shows data-health status: fixture file, live source, odds file, cache age, stale/broken warnings.
- Runs entirely locally with Node.js and browser HTML/JS.

## What it does not do

- It does not place bets.
- It does not guarantee predictions.
- It does not hide stale data behind a "live" label.
- It does not require paid APIs.
- It does not include official final World Cup 2026 fixture data before the draw/schedule is complete. The included fixture file is a starter/seed structure that you must update when official matches are available.

## Run locally

```powershell
cd Sports\FootballVMProphet
npm install
npm start
```

Open:

```text
http://localhost:8787
```

No dependencies are required beyond Node.js 18+. `npm install` is effectively a metadata check because the app uses only built-in Node modules.

## Free data model

VM Prophet uses three source layers:

1. `data/fixtures.worldcup2026.json` - local source of truth for fixtures.
2. Optional free live endpoint - configured with environment variable `FREE_LIVE_ENDPOINT` if you later find a free source.
3. `data/odds.manual.csv` - manual odds snapshots that you control.

If the live endpoint is not configured or fails, the dashboard stays usable and marks live data as disabled/broken/stale.

## Manual odds CSV

Copy the sample file:

```powershell
Copy-Item .\data\odds.manual.example.csv .\data\odds.manual.csv
```

Format:

```csv
matchId,snapshotTime,bookmaker,market,selection,odds
wc2026-g01-m01,2026-06-11T10:00:00+02:00,Manual,1X2,Home,1.95
wc2026-g01-m01,2026-06-11T10:00:00+02:00,Manual,1X2,Draw,3.40
wc2026-g01-m01,2026-06-11T10:00:00+02:00,Manual,1X2,Away,4.20
```

The app computes implied probability as `1 / decimal odds` and highlights movement between snapshots.

## Optional environment variables

```powershell
$env:VM_PROPHET_PORT = "8787"
$env:VM_PROPHET_TIMEZONE = "Europe/Oslo"
$env:FREE_LIVE_ENDPOINT = "https://example.invalid/free-live-football.json"
```

`FREE_LIVE_ENDPOINT` must return JSON shaped like:

```json
{
  "matches": [
    {
      "matchId": "wc2026-g01-m01",
      "status": "LIVE",
      "homeScore": 1,
      "awayScore": 0,
      "minute": 62,
      "updatedAt": "2026-06-11T19:22:00Z"
    }
  ]
}
```

## File layout

```text
Sports/FootballVMProphet/
├── package.json
├── README.md
├── data/
│   ├── fixtures.worldcup2026.json
│   ├── odds.manual.example.csv
│   └── watchlist.json
├── server/
│   ├── server.js
│   ├── cache/
│   └── sources/
│       ├── free-live-source.js
│       ├── local-fixtures.js
│       └── manual-odds.js
├── web/
│   ├── index.html
│   ├── app.js
│   └── styles.css
└── docs/
    ├── Data-Model.md
    └── Free-Source-Notes.md
```

## Betting warning

Use this as an evidence dashboard, not a prediction machine. Free sources may be delayed or wrong. The dashboard labels freshness so you can decide whether a signal is usable.
