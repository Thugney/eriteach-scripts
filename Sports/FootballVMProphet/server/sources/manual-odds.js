import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

function parseCsvLine(line) {
  const values = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      values.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  values.push(current.trim());
  return values;
}

function impliedProbability(decimalOdds) {
  const odds = Number(decimalOdds);
  if (!Number.isFinite(odds) || odds <= 1) return null;
  return Number((100 / odds).toFixed(2));
}

export function loadManualOdds(rootDir) {
  const oddsPath = path.join(rootDir, 'data', 'odds.manual.csv');
  const examplePath = path.join(rootDir, 'data', 'odds.manual.example.csv');
  const health = {
    ok: true,
    source: oddsPath,
    loadedAt: new Date().toISOString(),
    mode: 'manual',
    warnings: []
  };
  const sourcePath = existsSync(oddsPath) ? oddsPath : examplePath;
  if (!existsSync(oddsPath)) {
    health.warnings.push('No data/odds.manual.csv found. Loaded example odds only; betting board is sample/manual mode.');
  }
  try {
    const raw = readFileSync(sourcePath, 'utf8').trim();
    if (!raw) return { rows: [], summary: [], health };
    const lines = raw.split(/\r?\n/).filter(Boolean);
    const headers = parseCsvLine(lines.shift());
    const rows = lines.map((line) => {
      const values = parseCsvLine(line);
      const row = Object.fromEntries(headers.map((header, index) => [header, values[index] || '']));
      row.odds = Number(row.odds);
      row.impliedProbability = impliedProbability(row.odds);
      return row;
    });
    const grouped = new Map();
    for (const row of rows) {
      const key = `${row.matchId}|${row.market}|${row.selection}`;
      if (!grouped.has(key)) grouped.set(key, []);
      grouped.get(key).push(row);
    }
    const summary = [];
    for (const [key, group] of grouped.entries()) {
      group.sort((a, b) => new Date(a.snapshotTime) - new Date(b.snapshotTime));
      const first = group[0];
      const last = group[group.length - 1];
      summary.push({
        key,
        matchId: last.matchId,
        market: last.market,
        selection: last.selection,
        bookmaker: last.bookmaker,
        firstOdds: first.odds,
        latestOdds: last.odds,
        oddsMovement: Number((last.odds - first.odds).toFixed(3)),
        impliedProbability: last.impliedProbability,
        latestSnapshot: last.snapshotTime,
        sourceMode: existsSync(oddsPath) ? 'manual' : 'example'
      });
    }
    return { rows, summary, health };
  } catch (error) {
    health.ok = false;
    health.warnings.push(`Manual odds load failed: ${error.message}`);
    return { rows: [], summary: [], health };
  }
}
