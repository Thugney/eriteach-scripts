# Football VM Prophet

Free local web dashboard for FIFA World Cup 2026 men.

VM Prophet is a local command center for fixtures, live-status health, upcoming/past match filtering, and odds tracking. It is built for **free-first automatic data**: use free API keys for football-data.org and The Odds API, with loud stale/broken/fallback warnings when a source is missing or unavailable.

## What it does

- Lists FIFA World Cup 2026 matches from football-data.org when configured, otherwise local seed fixtures.
- Filters by today, live, upcoming, past, due soon, stage, team, venue, and data status.
- Shows detailed upcoming cards with countdown, venue, source freshness, and watchlist flags.
- Supports automatic odds from The Odds API, with manual CSV as fallback only.
- Calculates implied probability and movement from imported odds snapshots.
- Shows data-health status: fixture file, live source, odds file, cache age, stale/broken warnings.
- Runs entirely locally with Node.js and browser HTML/JS.

## What it does not do

- It does not place bets.
- It does not guarantee predictions.
- It does not hide stale data behind a "live" label.
- It does not require paid APIs, but single-pane automatic mode needs free API keys.
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

VM Prophet uses these source layers:

1. `FOOTBALL_DATA_API_KEY` - football-data.org free API key for fixtures, status and scores when the World Cup data is available.
2. `ODDS_API_KEY` - The Odds API free starter key for bookmaker odds when markets are available.
3. `FREE_LIVE_ENDPOINT` - optional custom JSON endpoint for your own live source if you have one.
4. `data/fixtures.worldcup2026.json` - local seed fallback if official API data is not available yet.
5. `data/odds.manual.csv` - manual fallback only; not required for automatic single-pane mode.

For setup steps, see `docs/Api-Setup.md`.

If the keys are not configured, the dashboard stays usable but marks football-data and odds as disabled/broken/stale.

## Automatic single-pane setup

Get free keys:

- football-data.org: `https://www.football-data.org/client/register`
- The Odds API: `https://the-odds-api.com/` -> **Get API Key** -> free starter tier

PowerShell:

```powershell
cd Sports\FootballVMProphet
$env:FOOTBALL_DATA_API_KEY = "paste-your-football-data-key-here"
$env:ODDS_API_KEY = "paste-your-odds-api-key-here"
$env:FOOTBALL_DATA_COMPETITION = "WC"
$env:FOOTBALL_DATA_DATE_FROM = "2026-06-01"
$env:FOOTBALL_DATA_DATE_TO = "2026-07-31"
npm install
npm test
npm start
```

Then open `http://localhost:8787`.

Do not commit API keys to GitHub. Keep them as environment variables or local secrets.

## Manual odds CSV fallback

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
│       ├── football-data-source.js
│       ├── odds-api-source.js
│       ├── free-live-source.js
│       ├── local-fixtures.js
│       └── manual-odds.js
├── web/
│   ├── index.html
│   ├── app.js
│   └── styles.css
└── docs/
    ├── Api-Setup.md
    ├── Data-Model.md
    └── Free-Source-Notes.md
```

## Betting warning

Use this as an evidence dashboard, not a prediction machine. Free sources may be delayed or wrong. The dashboard labels freshness so you can decide whether a signal is usable.
