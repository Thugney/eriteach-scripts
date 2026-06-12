# Free source notes

VM Prophet is intentionally free-first. That means:

- The local fixture file is the source of truth.
- Live scores are optional and best-effort.
- Paid API keys are not required.
- Betting odds are manual CSV/import based in v1.
- Stale/broken data is shown in the dashboard instead of hidden.

## Why not scrape betting sites?

Scraping bookmakers is brittle and can violate terms of service. It is also dangerous for betting decisions because the site layout or anti-bot response may silently break the data. VM Prophet avoids that in v1.

## Recommended workflow

1. Keep fixtures updated manually from official sources.
2. Use optional free live endpoint only as a convenience.
3. Import odds snapshots manually when you care about a market.
4. Treat stale warnings as blockers for betting decisions.
