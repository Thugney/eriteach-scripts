import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

function readCache(cachePath) {
  if (!existsSync(cachePath)) return null;
  try {
    return JSON.parse(readFileSync(cachePath, 'utf8'));
  } catch {
    return null;
  }
}

function impliedProbability(decimalOdds) {
  const value = Number(decimalOdds);
  if (!Number.isFinite(value) || value <= 0) return null;
  return Number((100 / value).toFixed(2));
}

function toDecimal(price) {
  const value = Number(price);
  if (!Number.isFinite(value)) return null;
  return Number(value.toFixed(2));
}

function marketLabel(key) {
  if (key === 'h2h') return '1X2';
  return key || 'market';
}

function selectionLabel(outcomeName, homeTeam, awayTeam) {
  if (outcomeName === homeTeam) return 'Home';
  if (outcomeName === awayTeam) return 'Away';
  if (String(outcomeName).toLowerCase() === 'draw') return 'Draw';
  return outcomeName;
}

function mapOddsEvent(event, fetchedAt) {
  const homeTeam = event.home_team || 'Home';
  const awayTeam = event.away_team || 'Away';
  const matchId = `odds-api-${String(event.id || `${homeTeam}-${awayTeam}-${event.commence_time}`).replace(/[^a-zA-Z0-9_-]/g, '-')}`;
  const rows = [];
  for (const bookmaker of event.bookmakers || []) {
    for (const market of bookmaker.markets || []) {
      for (const outcome of market.outcomes || []) {
        const odds = toDecimal(outcome.price);
        if (!odds) continue;
        rows.push({
          matchId,
          snapshotTime: bookmaker.last_update || fetchedAt,
          bookmaker: bookmaker.title || bookmaker.key || 'odds-api',
          market: marketLabel(market.key),
          selection: selectionLabel(outcome.name, homeTeam, awayTeam),
          odds,
          impliedProbability: impliedProbability(odds),
          oddsMovement: 0,
          firstOdds: odds,
          latestOdds: odds,
          sourceMode: 'odds-api',
          homeTeam,
          awayTeam,
          kickoffUtc: event.commence_time
        });
      }
    }
  }
  return rows;
}

export function fetchOddsApi(rootDir) {
  const apiKey = process.env.ODDS_API_KEY || '';
  const sport = process.env.ODDS_API_SPORT || 'soccer_fifa_world_cup';
  const regions = process.env.ODDS_API_REGIONS || 'eu,uk';
  const markets = process.env.ODDS_API_MARKETS || 'h2h';
  const oddsFormat = process.env.ODDS_API_FORMAT || 'decimal';
  const cacheDir = path.join(rootDir, 'server', 'cache');
  const cachePath = path.join(cacheDir, 'odds-api-cache.json');
  mkdirSync(cacheDir, { recursive: true });

  const health = {
    ok: false,
    source: 'the-odds-api.com',
    sport,
    regions,
    markets,
    fetchedAt: null,
    cacheUsed: false,
    warnings: []
  };

  if (!apiKey) {
    health.warnings.push('ODDS_API_KEY is not configured. Automatic bookmaker odds are disabled.');
    const cached = readCache(cachePath);
    if (cached) {
      health.cacheUsed = true;
      health.fetchedAt = cached.fetchedAt;
      health.warnings.push(`Cached odds data exists from ${cached.fetchedAt}, but no API key is configured. Treat it as stale.`);
      return { rows: cached.rows || [], summary: cached.summary || [], ok: false, source: 'odds-api-cache-stale', health };
    }
    return { rows: [], summary: [], ok: false, source: 'odds-api-disabled', health };
  }

  const url = `https://api.the-odds-api.com/v4/sports/${encodeURIComponent(sport)}/odds/?apiKey=${encodeURIComponent(apiKey)}&regions=${encodeURIComponent(regions)}&markets=${encodeURIComponent(markets)}&oddsFormat=${encodeURIComponent(oddsFormat)}`;
  try {
    const raw = execFileSync('curl', ['--fail', '--silent', '--show-error', '--max-time', '15', url], { encoding: 'utf8' });
    const parsed = JSON.parse(raw);
    const fetchedAt = new Date().toISOString();
    const rows = Array.isArray(parsed) ? parsed.flatMap((event) => mapOddsEvent(event, fetchedAt)) : [];
    const payload = { rows, summary: rows, fetchedAt, source: 'the-odds-api.com' };
    writeFileSync(cachePath, JSON.stringify(payload, null, 2), 'utf8');
    health.ok = true;
    health.fetchedAt = fetchedAt;
    if (!rows.length) {
      health.warnings.push('The Odds API returned zero odds rows. The selected World Cup sport key may not be active until fixtures/markets are available.');
    }
    return { ...payload, ok: true, health };
  } catch (error) {
    health.warnings.push(`The Odds API request failed: ${error.message}`);
    const cached = readCache(cachePath);
    if (cached) {
      health.cacheUsed = true;
      health.fetchedAt = cached.fetchedAt;
      health.warnings.push(`Showing cached odds data from ${cached.fetchedAt}. Treat as stale.`);
      return { rows: cached.rows || [], summary: cached.summary || [], ok: false, source: 'odds-api-cache-stale', health };
    }
    return { rows: [], summary: [], ok: false, source: 'odds-api-broken-no-cache', health };
  }
}
