# API setup - make Football VM Prophet automatic

Football VM Prophet can run in two modes:

1. **Automatic single-pane mode** using free API keys.
2. **Fixture-only fallback** when no API keys are configured.

If you want the dashboard to work without manually maintaining sources, configure the two free keys below.

## 1. Football fixtures and live status: football-data.org

Use this for official competition matches, kickoff times, match status and scores when available.

Get a free API key:

1. Go to `https://www.football-data.org/client/register`.
2. Register an account.
3. Confirm the email if requested.
4. Copy your API token from the football-data.org client area.

Free plan notes:

- football-data.org has a free tier.
- The API uses the `X-Auth-Token` request header.
- Rate limits apply. Do not refresh every second.
- FIFA World Cup competition code is `WC`.
- World Cup 2026 fixtures may return zero rows until the official schedule is available in the API.

PowerShell setup:

```powershell
$env:FOOTBALL_DATA_API_KEY = "<football-data-api-value>"
$env:FOOTBALL_DATA_COMPETITION = "WC"
$env:FOOTBALL_DATA_DATE_FROM = "2026-06-01"
$env:FOOTBALL_DATA_DATE_TO = "2026-07-31"
npm start
```

Linux/macOS setup:

```bash
export FOOTBALL_DATA_API_KEY="<football-data-api-value>"
export FOOTBALL_DATA_COMPETITION="WC"
export FOOTBALL_DATA_DATE_FROM="2026-06-01"
export FOOTBALL_DATA_DATE_TO="2026-07-31"
npm start
```

## 2. Automatic odds: The Odds API

Use this for bookmaker odds without maintaining `odds.manual.csv` yourself.

Get a free API key:

1. Go to `https://the-odds-api.com/`.
2. Select **Get API Key**.
3. Choose the free starter tier.
4. Copy the API key from the email/account page.

Free plan notes:

- The free plan has limited monthly credits.
- World Cup markets might not appear until bookmakers publish odds.
- Sport keys can change or be unavailable until the event is close.
- If the default sport key returns errors, check the `/v4/sports` endpoint in The Odds API documentation and set `ODDS_API_SPORT` accordingly.

PowerShell setup:

```powershell
$env:ODDS_API_KEY = "<odds-api-value>"
$env:ODDS_API_SPORT = "soccer_fifa_world_cup"
$env:ODDS_API_REGIONS = "eu,uk"
$env:ODDS_API_MARKETS = "h2h"
npm start
```

Linux/macOS setup:

```bash
export ODDS_API_KEY="<odds-api-value>"
export ODDS_API_SPORT="soccer_fifa_world_cup"
export ODDS_API_REGIONS="eu,uk"
export ODDS_API_MARKETS="h2h"
npm start
```

## 3. Recommended Windows one-session start

From the repo root:

```powershell
cd Sports\FootballVMProphet
$env:FOOTBALL_DATA_API_KEY = "<football-data-api-value>"
$env:ODDS_API_KEY = "<odds-api-value>"
npm install
npm test
npm start
```

Open:

```text
http://localhost:8787
```

## 4. What happens without keys

If you see this:

```text
FOOTBALL_DATA_API_KEY not configured. Official football-data.org sync is disabled.
ODDS_API_KEY not configured. Automatic odds are disabled.
```

The app is still working, but it is in fallback mode:

- local seed fixtures are used
- automatic live scores are disabled
- automatic bookmaker odds are disabled
- sample/manual odds may be shown only as examples

That mode is useful for testing the UI, but it is not the single-pane live view you want.

## 5. Security note

Do not commit API keys to GitHub.

Use environment variables, PowerShell profile entries, `.env` tooling outside the repo, or your local secret manager.
