# Free source notes

VM Prophet is free-first, but it should not be manual-first.

The intended single-pane setup is:

1. `FOOTBALL_DATA_API_KEY` from football-data.org for fixtures, statuses and scores.
2. `ODDS_API_KEY` from The Odds API for bookmaker odds.
3. Local seed fixtures only as fallback before official World Cup 2026 fixtures are published.
4. Manual odds CSV only as fallback if odds markets are not available or you want to track a bookmaker not covered by the free API.

## Free source limits

Free APIs are useful, but they are not magic:

- football-data.org has a free tier and rate limits.
- FIFA World Cup code is `WC`.
- World Cup 2026 data can return empty until the official schedule is available in the API.
- The Odds API free starter plan has limited monthly credits.
- World Cup odds may not be available until bookmakers publish markets.
- Sport keys can change; if `soccer_fifa_world_cup` fails, check The Odds API sports endpoint and update `ODDS_API_SPORT`.

## Why not scrape betting sites?

Scraping bookmakers is brittle and can violate terms of service. It is also dangerous for betting decisions because the site layout, anti-bot response, region lock, or delayed odds can silently break the data.

VM Prophet avoids scraping by default. Use The Odds API for automatic odds, or manual CSV only as an explicit fallback.

## Recommended workflow

1. Configure `FOOTBALL_DATA_API_KEY`.
2. Configure `ODDS_API_KEY`.
3. Start the app.
4. Check `/api/health` before trusting the dashboard.
5. Treat any `disabled`, `broken`, `cached`, `stale`, or `fixture-only` warning as a data-quality warning.

## Data-health rule

If a source is missing or stale, the dashboard must say so. Do not treat fallback data as live data.
