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

export function fetchFreeLive(rootDir) {
  const endpoint = process.env.FREE_LIVE_ENDPOINT || '';
  const cacheDir = path.join(rootDir, 'server', 'cache');
  const cachePath = path.join(cacheDir, 'free-live-cache.json');
  mkdirSync(cacheDir, { recursive: true });

  const health = {
    ok: false,
    source: endpoint || 'not-configured',
    fetchedAt: null,
    cacheUsed: false,
    warnings: []
  };

  if (!endpoint) {
    health.warnings.push('FREE_LIVE_ENDPOINT is not configured. Live scores are disabled; dashboard uses fixture/manual data only.');
    const cached = readCache(cachePath);
    if (cached) {
      health.cacheUsed = true;
      health.warnings.push('Old live cache exists but endpoint is disabled. Cached live data is not trusted as live.');
      return { matches: cached.matches || [], source: 'cache-disabled', fetchedAt: cached.fetchedAt, ok: false, health };
    }
    return { matches: [], source: 'disabled', fetchedAt: null, ok: false, health };
  }

  try {
    const raw = execFileSync('curl', ['--fail', '--silent', '--show-error', '--max-time', '10', endpoint], { encoding: 'utf8' });
    const parsed = JSON.parse(raw);
    const payload = {
      matches: Array.isArray(parsed.matches) ? parsed.matches : [],
      fetchedAt: new Date().toISOString(),
      source: endpoint
    };
    writeFileSync(cachePath, JSON.stringify(payload, null, 2), 'utf8');
    health.ok = true;
    health.fetchedAt = payload.fetchedAt;
    return { ...payload, ok: true, health };
  } catch (error) {
    health.warnings.push(`FREE_LIVE_ENDPOINT failed: ${error.message}`);
    const cached = readCache(cachePath);
    if (cached) {
      health.cacheUsed = true;
      health.fetchedAt = cached.fetchedAt;
      health.warnings.push(`Showing cached live data from ${cached.fetchedAt}. Treat as stale.`);
      return { matches: cached.matches || [], source: 'cache-stale', fetchedAt: cached.fetchedAt, ok: false, health };
    }
    return { matches: [], source: 'broken-no-cache', fetchedAt: null, ok: false, health };
  }
}
