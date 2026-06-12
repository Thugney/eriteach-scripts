import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadFixtures } from './sources/local-fixtures.js';
import { loadManualOdds } from './sources/manual-odds.js';
import { fetchFreeLive } from './sources/free-live-source.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');
const port = Number(process.env.VM_PROPHET_PORT || 8787);
const timezone = process.env.VM_PROPHET_TIMEZONE || 'Europe/Oslo';

function jsonResponse(res, statusCode, body) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(payload);
}

function textResponse(res, statusCode, contentType, body) {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function mergeLive(fixtures, liveResult) {
  const liveById = new Map((liveResult.matches || []).map((m) => [m.matchId, m]));
  return fixtures.matches.map((match) => {
    const live = liveById.get(match.matchId);
    if (!live) {
      return {
        ...match,
        dataStatus: match.status === 'scheduled' ? 'fixture-only' : 'fixture-only',
        liveSource: 'none'
      };
    }
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

function buildDashboard() {
  const fixtures = loadFixtures(rootDir);
  const odds = loadManualOdds(rootDir);
  const live = fetchFreeLive(rootDir);
  const matches = mergeLive(fixtures, live);
  const health = {
    generatedAt: new Date().toISOString(),
    timezone,
    fixtures: fixtures.health,
    live: live.health,
    odds: odds.health,
    warnings: [
      ...fixtures.health.warnings,
      ...live.health.warnings,
      ...odds.health.warnings
    ]
  };
  return {
    tournament: fixtures.tournament,
    timezone,
    matches,
    odds: odds.rows,
    oddsSummary: odds.summary,
    health
  };
}

async function serveStatic(req, res) {
  const urlPath = new URL(req.url, `http://localhost:${port}`).pathname;
  const safePath = urlPath === '/' ? '/index.html' : urlPath;
  const filePath = path.resolve(rootDir, 'web', `.${safePath}`);
  if (!filePath.startsWith(path.resolve(rootDir, 'web'))) {
    textResponse(res, 403, 'text/plain; charset=utf-8', 'Forbidden');
    return;
  }
  if (!existsSync(filePath)) {
    textResponse(res, 404, 'text/plain; charset=utf-8', 'Not found');
    return;
  }
  const ext = path.extname(filePath).toLowerCase();
  const types = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8'
  };
  const body = await readFile(filePath);
  textResponse(res, 200, types[ext] || 'application/octet-stream', body);
}

export function createServer() {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://localhost:${port}`);
      if (url.pathname === '/api/dashboard') {
        jsonResponse(res, 200, buildDashboard());
        return;
      }
      if (url.pathname === '/api/health') {
        jsonResponse(res, 200, buildDashboard().health);
        return;
      }
      await serveStatic(req, res);
    } catch (error) {
      jsonResponse(res, 500, {
        ok: false,
        error: error.message,
        warning: 'VM Prophet failed to build a response. Check server console and data files.'
      });
    }
  });
}

if (process.argv.includes('--self-test')) {
  const dashboard = buildDashboard();
  if (!dashboard.matches.length) {
    throw new Error('Self-test failed: no fixtures loaded');
  }
  if (!dashboard.health.fixtures.ok) {
    throw new Error(`Self-test failed: fixture health not OK: ${dashboard.health.fixtures.warnings.join('; ')}`);
  }
  console.log(JSON.stringify({ ok: true, matches: dashboard.matches.length, warnings: dashboard.health.warnings }, null, 2));
} else {
  createServer().listen(port, () => {
    console.log(`Football VM Prophet running at http://localhost:${port}`);
    console.log(`Timezone: ${timezone}`);
    if (!process.env.FREE_LIVE_ENDPOINT) {
      console.log('FREE_LIVE_ENDPOINT not configured. Live data will be marked as disabled/fixture-only.');
    }
  });
}
