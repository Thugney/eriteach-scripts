let dashboard = null;

const els = {
  healthBanner: document.getElementById('healthBanner'),
  matches: document.getElementById('matches'),
  oddsBoard: document.getElementById('oddsBoard'),
  healthDetails: document.getElementById('healthDetails'),
  stats: document.getElementById('stats'),
  lastRefresh: document.getElementById('lastRefresh'),
  viewFilter: document.getElementById('viewFilter'),
  teamFilter: document.getElementById('teamFilter'),
  stageFilter: document.getElementById('stageFilter'),
  venueFilter: document.getElementById('venueFilter'),
  searchFilter: document.getElementById('searchFilter'),
  refreshButton: document.getElementById('refreshButton')
};

function asDate(value) {
  return value ? new Date(value) : null;
}

function fmtDate(value, timezone) {
  const date = asDate(value);
  if (!date || Number.isNaN(date.getTime())) return 'Unknown';
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone,
    dateStyle: 'medium',
    timeStyle: 'short'
  }).format(date);
}

function countdown(value) {
  const date = asDate(value);
  if (!date) return 'Unknown';
  const ms = date.getTime() - Date.now();
  if (ms < 0) return 'Started / past';
  const hours = Math.floor(ms / 36e5);
  const days = Math.floor(hours / 24);
  const remHours = hours % 24;
  const minutes = Math.floor((ms % 36e5) / 60000);
  return `${days}d ${remHours}h ${minutes}m`;
}

function isToday(value) {
  const date = asDate(value);
  const now = new Date();
  return date && date.toDateString() === now.toDateString();
}

function statusClass(status) {
  const s = String(status || '').toLowerCase();
  if (s.includes('live')) return 'live';
  if (s.includes('final') || s.includes('past')) return 'past';
  return 'upcoming';
}

function renderHealth() {
  const warnings = dashboard.health.warnings || [];
  const broken = warnings.length > 0 || !dashboard.health.fixtures.ok || !dashboard.health.live.ok;
  els.healthBanner.className = broken ? 'health-banner broken' : 'health-banner ok';
  els.healthBanner.textContent = broken
    ? `DATA WARNING: ${warnings[0] || 'One or more sources are not healthy.'}`
    : 'DATA OK: fixtures loaded and no source warnings.';
  els.healthDetails.textContent = JSON.stringify(dashboard.health, null, 2);
}

function getFilteredMatches() {
  const view = els.viewFilter.value;
  const team = els.teamFilter.value.trim().toLowerCase();
  const stage = els.stageFilter.value.trim().toLowerCase();
  const venue = els.venueFilter.value.trim().toLowerCase();
  const search = els.searchFilter.value.trim().toLowerCase();
  const now = Date.now();
  const dueMs = 24 * 36e5;

  return dashboard.matches.filter((match) => {
    const kickoff = asDate(match.kickoffUtc)?.getTime() || 0;
    const status = String(match.status || '').toLowerCase();
    const haystack = `${match.homeTeam} ${match.awayTeam} ${match.stage} ${match.group || ''} ${match.venue || ''} ${match.city || ''} ${match.dataStatus}`.toLowerCase();

    if (view === 'today' && !isToday(match.kickoffUtc)) return false;
    if (view === 'live' && !status.includes('live')) return false;
    if (view === 'upcoming' && kickoff <= now) return false;
    if (view === 'past' && kickoff >= now && !status.includes('final')) return false;
    if (view === 'due' && !(kickoff > now && kickoff - now <= dueMs)) return false;
    if (view === 'stale' && !['fixture-only', 'cached-or-broken'].includes(match.dataStatus)) return false;
    if (team && !`${match.homeTeam} ${match.awayTeam}`.toLowerCase().includes(team)) return false;
    if (stage && !String(match.stage || '').toLowerCase().includes(stage)) return false;
    if (venue && !`${match.venue || ''} ${match.city || ''}`.toLowerCase().includes(venue)) return false;
    if (search && !haystack.includes(search)) return false;
    return true;
  }).sort((a, b) => new Date(a.kickoffUtc) - new Date(b.kickoffUtc));
}

function renderStats(matches) {
  const now = Date.now();
  const live = dashboard.matches.filter((m) => String(m.status).toLowerCase().includes('live')).length;
  const upcoming = dashboard.matches.filter((m) => new Date(m.kickoffUtc).getTime() > now).length;
  const due = dashboard.matches.filter((m) => {
    const kickoff = new Date(m.kickoffUtc).getTime();
    return kickoff > now && kickoff - now <= 24 * 36e5;
  }).length;
  const stale = dashboard.matches.filter((m) => ['fixture-only', 'cached-or-broken'].includes(m.dataStatus)).length;
  els.stats.innerHTML = [
    ['Shown', matches.length], ['Live', live], ['Upcoming', upcoming], ['Due 24h', due], ['Stale/fixture-only', stale]
  ].map(([label, value]) => `<div class="stat"><strong>${value}</strong><span>${label}</span></div>`).join('');
}

function renderMatches() {
  const matches = getFilteredMatches();
  renderStats(matches);
  if (!matches.length) {
    els.matches.innerHTML = '<div class="empty">No matches for current filters.</div>';
    return;
  }
  els.matches.innerHTML = matches.map((match) => {
    const score = Number.isFinite(match.homeScore) && Number.isFinite(match.awayScore)
      ? `${match.homeScore} - ${match.awayScore}`
      : 'vs';
    const dataTag = match.dataStatus === 'live' ? 'LIVE DATA' : String(match.dataStatus || 'unknown').toUpperCase();
    return `<article class="match-card ${statusClass(match.status)}">
      <div class="match-main">
        <div class="teams"><span>${match.homeTeam}</span><b>${score}</b><span>${match.awayTeam}</span></div>
        <div class="meta">${match.stage}${match.group ? ` / ${match.group}` : ''} · ${match.venue || 'Venue TBD'}${match.city ? `, ${match.city}` : ''}</div>
        <div class="meta">Kickoff: ${fmtDate(match.kickoffUtc, dashboard.timezone)} · Countdown: ${countdown(match.kickoffUtc)}</div>
      </div>
      <div class="badges">
        <span class="badge ${statusClass(match.status)}">${match.status}</span>
        <span class="badge data">${dataTag}</span>
        ${match.minute ? `<span class="badge">${match.minute}'</span>` : ''}
      </div>
    </article>`;
  }).join('');
}

function renderOdds() {
  const rows = dashboard.oddsSummary || [];
  if (!rows.length) {
    els.oddsBoard.innerHTML = '<div class="empty">No manual odds loaded. Copy data/odds.manual.example.csv to data/odds.manual.csv and update it.</div>';
    return;
  }
  els.oddsBoard.innerHTML = rows.map((row) => {
    const match = dashboard.matches.find((m) => m.matchId === row.matchId);
    const movement = row.oddsMovement > 0 ? `+${row.oddsMovement}` : `${row.oddsMovement}`;
    const movementClass = row.oddsMovement < 0 ? 'shortened' : row.oddsMovement > 0 ? 'drifted' : 'flat';
    return `<div class="odds-row">
      <strong>${match ? `${match.homeTeam} vs ${match.awayTeam}` : row.matchId}</strong>
      <span>${row.market} / ${row.selection}</span>
      <span>${row.firstOdds} → ${row.latestOdds}</span>
      <span class="${movementClass}">${movement}</span>
      <span>Implied: ${row.impliedProbability ?? 'n/a'}%</span>
      <span class="tag">${row.sourceMode}</span>
    </div>`;
  }).join('');
}

function render() {
  renderHealth();
  renderMatches();
  renderOdds();
  els.lastRefresh.textContent = `Last refresh: ${fmtDate(dashboard.health.generatedAt, dashboard.timezone)}`;
}

async function loadDashboard() {
  els.healthBanner.textContent = 'Loading...';
  const response = await fetch('/api/dashboard', { cache: 'no-store' });
  dashboard = await response.json();
  render();
}

['change', 'input'].forEach((eventName) => {
  [els.viewFilter, els.teamFilter, els.stageFilter, els.venueFilter, els.searchFilter].forEach((el) => {
    el.addEventListener(eventName, () => dashboard && renderMatches());
  });
});
els.refreshButton.addEventListener('click', loadDashboard);
loadDashboard().catch((error) => {
  els.healthBanner.className = 'health-banner broken';
  els.healthBanner.textContent = `APP BROKEN: ${error.message}`;
});
