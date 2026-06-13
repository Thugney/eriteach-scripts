import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadFixtures } from './sources/local-fixtures.js';
import { loadManualOdds } from './sources/manual-odds.js';
import { fetchFreeLive } from './sources/free-live-source.js';
import { fetchFootballData } from './sources/football-data-source.js';
import { fetchOddsApi } from './sources/odds-api-source.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');
const port = Number(process.env.VM_PROPHET_PORT || 8787);
const timezone = process.env.VM_PROPHET_TIMEZONE || 'Europe/Oslo';

function jsonResponse(res, statusCode, body) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body, null, 2));
}

function textResponse(res, statusCode, contentType, body) {
  res.writeHead(statusCode, { 'Content-Type': contentType, 'Cache-Control': 'no-store' });
  res.end(body);
}

function mergeLive(fixtures, liveResult) {
  const liveById = new Map((liveResult.matches || []).map((m) => [m.matchId, m]));
  return fixtures.matches.map((match) => {
    const live = liveById.get(match.matchId);
    if (!live) return { ...match, dataStatus: 'fixture-only', liveSource: 'none' };
    return {
      ...match,
      status: live.status || match.status,
      homeScore: Number.isFinite(Number(live.homeScore)) ? Number(live.homeScore) : match.homeScore,
      awayScore: Number.isFinite(Number(live.awayScore)) ? Number(live.awayScore) : match.awayScore,
      minute: live.minute ?? match.minute,
      liveUpdatedAt: live.updatedAt || liveResult.fetchedAt,
      dataStatus: liveResult.ok ? 'live' : 'cached-or-broken',
      liveSource: liveResult.source
    };
  });
}

function chooseMatches(fixtures, footballData, live) {
  if (footballData.matches?.length) return footballData.matches.map((match) => ({ ...match, dataStatus: footballData.ok ? 'football-data' : 'cached-or-broken' }));
  return mergeLive(fixtures, live);
}

function chooseOdds(manualOdds, oddsApi) {
  if (oddsApi.rows?.length) return { rows: oddsApi.rows, summary: oddsApi.summary, health: oddsApi.health, mode: 'odds-api' };
  return { rows: manualOdds.rows, summary: manualOdds.summary, health: manualOdds.health, mode: 'manual-or-example' };
}

function buildDashboard() {
  const fixtures = loadFixtures(rootDir);
  const manualOdds = loadManualOdds(rootDir);
  const live = fetchFreeLive(rootDir);
  const footballData = fetchFootballData(rootDir);
  const oddsApi = fetchOddsApi(rootDir);
  const selectedOdds = chooseOdds(manualOdds, oddsApi);
  const matches = chooseMatches(fixtures, footballData, live);
  const health = {
    generatedAt: new Date().toISOString(),
    timezone,
    fixtures: fixtures.health,
    footballData: footballData.health,
    live: live.health,
    oddsApi: oddsApi.health,
    odds: selectedOdds.health,
    oddsMode: selectedOdds.mode,
    warnings: [
      ...fixtures.health.warnings,
      ...footballData.health.warnings,
      ...live.health.warnings,
      ...oddsApi.health.warnings,
      ...(selectedOdds.mode === 'manual-or-example' ? manualOdds.health.warnings : [])
    ]
  };
  return { tournament: fixtures.tournament, timezone, matches, odds: selectedOdds.rows, oddsSummary: selectedOdds.summary, health };
}

async function serveStatic(req, res) {
  const urlPath = new URL(req.url, `http://localhost:${port}`).pathname;
  const safePath = urlPath === '/' ? '/index.html' : urlPath;
  const webRoot = path.resolve(rootDir, 'web');
  const filePath = path.resolve(webRoot, `.${safePath}`);
  if (!filePath.startsWith(webRoot)) return textResponse(res, 403, 'text/plain; charset=utf-8', 'Forbidden');
  if (!existsSync(filePath)) return textResponse(res, 404, 'text/plain; charset=utf-8', 'Not found');
  const ext = path.extname(filePath).toLowerCase();
  const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8' };
  textResponse(res, 200, types[ext] || 'application/octet-stream', await readFile(filePath));
}

export function createServer() {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://localhost:${port}`);
      if (url.pathname === '/api/dashboard') return jsonResponse(res, 200, buildDashboard());
      if (url.pathname === '/api/health') return jsonResponse(res, 200, buildDashboard().health);
      await serveStatic(req, res);
    } catch (error) {
      jsonResponse(res, 500, { ok: false, error: error.message, warning: 'VM Prophet failed to build a response. Check server console and data files.' });
    }
  });
}

if (process.argv.includes('--self-test')) {
  const dashboard = buildDashboard();
  if (!dashboard.matches.length) throw new Error('Self-test failed: no fixtures loaded');
  if (!dashboard.health.fixtures.ok) throw new Error(`Self-test failed: fixture health not OK: ${dashboard.health.fixtures.warnings.join('; ')}`);
  console.log(JSON.stringify({ ok: true, matches: dashboard.matches.length, warnings: dashboard.health.warnings }, null, 2));
} else {
  createServer().listen(port, () => {
    console.log(`Football VM Prophet running at http://localhost:${port}`);
    console.log(`Timezone: ${timezone}`);
    if (!process.env.FOOTBALL_DATA_API_KEY) console.log('FOOTBALL_DATA_API_KEY not configured. Official football-data.org sync is disabled.');
    if (!process.env.ODDS_API_KEY) console.log('ODDS_API_KEY not configured. Automatic odds are disabled.');
    if (!process.env.FREE_LIVE_ENDPOINT) console.log('FREE_LIVE_ENDPOINT not configured. Generic custom live endpoint is disabled.');
  });
}
