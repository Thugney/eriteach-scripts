import { readFileSync } from 'node:fs';
import path from 'node:path';

export function loadFixtures(rootDir) {
  const fixturePath = path.join(rootDir, 'data', 'fixtures.worldcup2026.json');
  const health = { ok: true, source: fixturePath, loadedAt: new Date().toISOString(), warnings: [] };
  try {
    const parsed = JSON.parse(readFileSync(fixturePath, 'utf8'));
    if (!Array.isArray(parsed.matches)) throw new Error('fixtures.worldcup2026.json must contain a matches array');
    for (const match of parsed.matches) {
      if (!match.matchId || !match.kickoffUtc || !match.homeTeam || !match.awayTeam) {
        health.warnings.push(`Fixture ${match.matchId || 'unknown'} is missing required fields.`);
      }
    }
    if (parsed.dataQuality === 'seed') health.warnings.push('Fixture file is seed data. Replace with official FIFA 2026 fixtures when available.');
    return { tournament: parsed.tournament || { name: 'FIFA World Cup 2026' }, matches: parsed.matches, health };
  } catch (error) {
    health.ok = false;
    health.warnings.push(`Fixture load failed: ${error.message}`);
    return { tournament: { name: 'FIFA World Cup 2026' }, matches: [], health };
  }
}
