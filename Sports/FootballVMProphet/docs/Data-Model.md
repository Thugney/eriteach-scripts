# VM Prophet data model

## Fixture fields

- `matchId` - stable local ID used to join fixtures, live scores, and odds.
- `stage` - Group Stage, Round of 32, Round of 16, Quarter-final, Semi-final, Final.
- `group` - group name or Knockout.
- `homeTeam` / `awayTeam` - team labels. Use TBD until official schedule is known.
- `kickoffUtc` - ISO timestamp in UTC.
- `venue` / `city` - stadium and city.
- `status` - scheduled, live, final, postponed, cancelled.
- `homeScore` / `awayScore` - null until known.

## Live endpoint shape

Optional `FREE_LIVE_ENDPOINT` should return:

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

## Manual odds CSV

- `matchId`
- `snapshotTime`
- `bookmaker`
- `market`
- `selection`
- `odds`

Decimal odds only in v1.
