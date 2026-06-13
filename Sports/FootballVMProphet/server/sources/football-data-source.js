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

function normalizeStatus(status) {
  const value = String(status || '').toUpperCase();
  if (['IN_PLAY', 'PAUSED'].includes(value)) return 'live';
  if (['FINISHED', 'AWARDED'].includes(value)) return 'final';
  if (['POSTPONED', 'SUSPENDED', 'CANCELLED'].includes(value)) return value.toLowerCase();
  return 'scheduled';
}

function mapMatch(match) {
  const homeName = match?.homeTeam?.name || match?.homeTeam?.shortName || 'TBD home';
  const awayName = match?.awayTeam?.name || match?.awayTeam?.shortName || 'TBD away';
  const fullTime = match?.score?.fullTime || {};
  const regularTime = match?.score?.regularTime || {};
  const homeScore = Number.isFinite(Number(fullTime.home)) ? Number(fullTime.home)
    : Number.isFinite(Number(regularTime.home)) ? Number(regularTime.home)
      : null;
  const awayScore = Number.isFinite(Number(fullTime.away)) ? Number(fullTime.away)
    : Number.isFinite(Number(regularTime.away)) ? Number(regularTime.away)
      : null;

  return {
    matchId: `football-data-${match.id}`,
    externalId: String(match.id),
    stage: match.stage || (match.matchday ? `Matchday ${match.matchday}` : 'World Cup'),
    group: match.group || '',
    homeTeam: homeName,
    awayTeam: awayName,
    kickoffUtc: match.utcDate,
    venue: match.venue || 'Venue TBD',
    city: '',
    status: normalizeStatus(match.status),
    homeScore,
    awayScore,
    minute: match.minute || null,
    dataStatus: 'football-data',
    liveSource: 'football-data.org',
    liveUpdatedAt: match.lastUpdated || null
  };
}

export function fetchFootballData(rootDir) {
  const apiKey = process.env.FOOTBALL_DATA_API_KEY || '';
  const competition = process.env.FOOTBALL_DATA_COMPETITION || 'WC';
  const dateFrom = process.env.FOOTBALL_DATA_DATE_FROM || '2026-06-01';
  const dateTo = process.env.FOOTBALL_DATA_DATE_TO || '2026-07-31';
  const cacheDir = path.join(rootDir, 'server', 'cache');
  const cachePath = path.join(cacheDir, 'football-data-cache.json');
  mkdirSync(cacheDir, { recursive: true });

  const health = {
    ok: false,
    source: 'football-data.org',
    competition,
    dateFrom,
    dateTo,
    fetchedAt: null,
    cacheUsed: false,
    warnings: []
  };

  if (!apiKey) {
    health.warnings.push('FOOTBALL_DATA_API_KEY is not configured. Official fixture/live sync is disabled; dashboard uses local seed fixtures.');
    const cached = readCache(cachePath);
    if (cached) {
      health.cacheUsed = true;
      health.fetchedAt = cached.fetchedAt;
      health.warnings.push(`Cached football-data.org data exists from ${cached.fetchedAt}, but no API key is configured. Treat it as stale.`);
      return { matches: cached.matches || [], ok: false, source: 'football-data-cache-stale', health };
    }
    return { matches: [], ok: false, source: 'football-data-disabled', health };
  }

  const url = `https://api.football-data.org/v4/competitions/${encodeURIComponent(competition)}/matches?dateFrom=${encodeURIComponent(dateFrom)}&dateTo=${encodeURIComponent(dateTo)}`;
  try {
    const raw = execFileSync('curl', [
      '--fail', '--silent', '--show-error', '--max-time', '15',
      '-H', `X-Auth-Token: ${apiKey}`,
      url
    ], { encoding: 'utf8' });
    const parsed = JSON.parse(raw);
    const matches = Array.isArray(parsed.matches) ? parsed.matches.map(mapMatch) : [];
    const payload = {
      matches,
      fetchedAt: new Date().toISOString(),
      source: 'football-data.org',
      rawCount: Array.isArray(parsed.matches) ? parsed.matches.length : 0
    };
    writeFileSync(cachePath, JSON.stringify(payload, null, 2), 'utf8');
    health.ok = true;
    health.fetchedAt = payload.fetchedAt;
    if (!matches.length) {
      health.warnings.push('football-data.org returned zero matches for the configured competition/date range. This can happen before the official schedule is published.');
    }
    return { ...payload, ok: true, health };
  } catch (error) {
    health.warnings.push(`football-data.org request failed: ${error.message}`);
    const cached = readCache(cachePath);
    if (cached) {
      health.cacheUsed = true;
      health.fetchedAt = cached.fetchedAt;
      health.warnings.push(`Showing cached football-data.org data from ${cached.fetchedAt}. Treat as stale.`);
      return { matches: cached.matches || [], ok: false, source: 'football-data-cache-stale', health };
    }
    return { matches: [], ok: false, source: 'football-data-broken-no-cache', health };
  }
}
