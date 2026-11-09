// Onboarding mockups: icons, sample Silo data, the Library tab landing, and a tiny scripted-remote engine.
// Each page sets window.SCRIPT = async () => { ... } and the engine plays it.
//   ?raw   1920×1080 unscaled (used for recording)
//   ?rec   play once, then set window.__done (used for recording)

const ICONS = {
  search: '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/>',
  home: '<path class="f" d="M4 10.4 12 3.8l8 6.6V20h-5.2v-5.6H9.2V20H4z"/>',
  download: '<path d="M12 4v10M7.5 9.6 12 14l4.5-4.4M5 19.5h14"/>',
  movie: '<rect x="3" y="6" width="18" height="13.5" rx="1.6"/><path d="M3 10.5h18M7.5 6l2 4.5M12.5 6l2 4.5M17.5 6l2 4.5"/>',
  tv: '<rect x="3" y="4.5" width="18" height="13" rx="1.6"/><path d="M8.5 20.5h7"/>',
  bookmark: '<path d="M6.8 3.8h10.4c.4 0 .8.4.8.8v15.6l-6-3.9-6 3.9V4.6c0-.4.4-.8.8-.8z"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2.8l1.6 2.3 2.7-.6.9 2.6 2.6.9-.6 2.7 2.3 1.6-2.3 1.6.6 2.7-2.6.9-.9 2.6-2.7-.6L12 21.2l-1.6-2.3-2.7.6-.9-2.6-2.6-.9.6-2.7L2.5 12l2.3-1.6-.6-2.7 2.6-.9.9-2.6 2.7.6z"/>',
  refresh: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4v5h-5"/>',
  people: '<circle cx="9" cy="8.2" r="3.4"/><path d="M2.8 19.5c.3-3.4 2.9-5.6 6.2-5.6s5.9 2.2 6.2 5.6zM15.4 4.9a3.4 3.4 0 0 1 0 6.6M17.6 14.2c2 .7 3.3 2.6 3.6 5.3"/>',
  phone: '<rect x="7" y="2.5" width="10" height="19" rx="2"/><path d="M11.2 18.2h1.6"/>',
  check: '<path d="M5 12.6l4.4 4.4L19 7.4"/>',
  close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  left: '<path d="M14.5 6 8.5 12l6 6"/>',
  right: '<path d="M9.5 6l6 6-6 6"/>',
  up: '<path d="M6 14.5l6-6 6 6"/>',
  down: '<path d="M6 9.5l6 6 6-6"/>',
  back: '<path d="M9 7 4.5 11.5 9 16"/><path d="M5 11.5h9.5a5 5 0 0 1 0 10H12"/>',
  add: '<path d="M12 5v14M5 12h14"/>',
  server: '<rect x="4" y="4" width="16" height="6.5" rx="1.6"/><rect x="4" y="13.5" width="16" height="6.5" rx="1.6"/><path d="M7.5 7.25h.01M7.5 16.75h.01"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l8.5-8.5M16.5 6.5l2.5 2.5M14 9l2 2"/>',
  pin: '<path d="M9 3.5h6M10 3.5v6.2L6.5 13.5h11L14 9.7V3.5M12 13.5V21"/>',
  edit: '<path d="M4.5 19.5h4l10-10-4-4-10 10zM13 7l4 4"/>',
  play: '<path class="f" d="M8 5.2v13.6L18.6 12z"/>',
  sparkle: '<path d="M12 3.5v4M12 16.5v4M3.5 12h4M16.5 12h4M6 6l2.6 2.6M15.4 15.4 18 18M18 6l-2.6 2.6M8.6 15.4 6 18"/>',
  grid: '<rect x="4" y="4" width="6.5" height="6.5" rx="1.2"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.2"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.2"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.2"/>',
};

const A = (n) => `assets/${n}.jpg`;

// Sample Silo server data. Names and counts are placeholders; library posters are real library art.
const SERVER = { host: 'silo.ashgrove.net', name: 'Ashgrove', link: 'silo.ashgrove.net/link', code: 'K7QM-24RX' };
const PROFILES = [
  { id: 'sam', name: 'Sam', tint: '#4a4d57' },
  { id: 'jo', name: 'Jo', tint: '#3d4a52' },
  { id: 'kids', name: 'Kids', tint: '#4d4652', pin: true },
];
const LIBS = [
  { id: 'movies', name: 'Movies', icon: 'movie', count: '1,842 movies', posters: ['s-avatar', 's-talladega', 's-michael'] },
  { id: 'shows', name: 'TV Shows', icon: 'tv', count: '312 shows', posters: ['s-supergirl', 's-paradise', 's-dastaar'] },
  { id: 'anime', name: 'Anime', icon: 'tv', count: '88 shows', posters: ['s-hxh', 's-mononoke', 's-hei'] },
  { id: 'kids', name: 'Kids', icon: 'movie', count: '230 titles', posters: ['s-ponyo', 's-duck', 's-tunnel'] },
  { id: 'sports', name: 'Fight Night', icon: 'tv', count: '146 events', posters: ['s-whittaker', 's-runitback', 's-silva'] },
  { id: 'world', name: 'World Cinema', icon: 'movie', count: '204 movies', posters: ['s-bombay', 's-hawa', 's-adinaasam'] },
];
// "n" = titles of this network already in the Silo library (TMDB only matches; cards come from Silo).
const NETWORKS = {
  Streaming: [
    ['Netflix', 214], ['Prime Video', 96], ['HBO', 131], ['Paramount+', 58], ['Disney+', 77],
    ['Apple TV', 42], ['Hulu', 63], ['Peacock', 21], ['Crunchyroll', 49], ['STARZ', 17],
  ],
  'US channels': [
    ['AMC', 27], ['FX', 33], ['Showtime', 24], ['NBC', 19], ['ABC', 16],
    ['CBS', 22], ['Adult Swim', 14], ['Comedy Central', 11], ['Syfy', 9], ['History', 8],
  ],
  'UK channels': [
    ['BBC One', 38], ['BBC Two', 21], ['BBC Three', 9], ['ITV1', 26], ['Channel 4', 18], ['Sky Atlantic', 15],
  ],
};
const DEFAULT_NETWORKS = ['Netflix', 'Prime Video', 'HBO', 'Paramount+'];
const GENRES = ['Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', 'Drama', 'Family', 'Fantasy',
  'History', 'Horror', 'Kids', 'Music', 'Mystery', 'Reality', 'Romance', 'Science Fiction', 'Thriller', 'War', 'Western'];
const DEFAULT_GENRES = ['Action', 'Comedy', 'Drama', 'Horror', 'Science Fiction', 'Animation'];
const GENRE_ART = { Action: 's-bullet', Comedy: 's-talladega', Drama: 's-mothers', Horror: 's-hauntedween', 'Science Fiction': 's-avatar',
  Animation: 's-ponyo', Documentary: 's-notebook', Crime: 's-hitlist', Thriller: 's-obsession', Fantasy: 's-mononoke', Romance: 's-mrmrs', Family: 's-duck' };

const ic = (n, cls = '') => `<svg class="i ${cls}"><use href="#i-${n}"/></svg>`;
const fan = (lib, w = 54) => {
  const h = Math.round(w * 1.5), W = Math.round(w * 2.1);
  return `<div class="fan" style="width:${W}px;height:${h + 6}px">` + lib.posters.map((p, i) =>
    `<img src="${A(p)}" style="width:${w}px;height:${h}px;left:${i * w * 0.55}px;transform:rotate(${(i - 1) * 6}deg);z-index:${i === 1 ? 3 : 1}">`).join('') + '</div>';
};
const ntile = (name, n, on) => `<div class="ntile${on ? ' on' : ''}" data-net="${name}"><span class="wm">${name}</span><span class="cnt">${n} in your library</span><span class="tick">${ic('check')}</span></div>`;

// Decorative QR stand-in: three finder squares and seeded modules.
function qr(size = 260) {
  let s = 7, rnd = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  const N = 29, cells = [];
  const finder = (x, y) => (x >= 0 && x < 7 && y >= 0 && y < 7);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const inF = finder(x, y) || finder(x - (N - 7), y) || finder(x, y - (N - 7));
    if (inF) continue;
    if ((x < 8 && y < 8) || (x > N - 9 && y < 8) || (x < 8 && y > N - 9)) continue;
    if (rnd() > 0.52) cells.push(`<rect x="${x}" y="${y}" width="1.02" height="1.02"/>`);
  }
  const f = (x, y) => `<rect x="${x}" y="${y}" width="7" height="7"/><rect x="${x + 1}" y="${y + 1}" width="5" height="5" fill="#fff"/><rect x="${x + 2}" y="${y + 2}" width="3" height="3"/>`;
  return `<div class="qr" style="width:${size}px;height:${size}px"><svg viewBox="0 0 ${N} ${N}" fill="#0e0f12" shape-rendering="crispEdges">${f(0, 0)}${f(N - 7, 0)}${f(0, N - 7)}${cells.join('')}</svg></div>`;
}

// The Library tab the flow lands on. opts: { libs, networks, genres, name, ghost }
function homeHTML(o = {}) {
  const libs = o.libs ?? LIBS.slice(0, 4).map((l) => l.id);
  const nets = o.networks ?? DEFAULT_NETWORKS;
  const gens = o.genres ?? DEFAULT_GENRES;
  const all = Object.values(NETWORKS).flat();
  const libItems = LIBS.map((l) => `<div class="item lib${libs.includes(l.id) ? '' : ' gone'}" data-lib="${l.id}">${ic(l.icon)}</div>`).join('');
  return `<div class="home${o.ghost ? ' ghost' : ''}">
    <nav class="rail"><div class="avatar">${(o.name ?? 'Sam')[0]}</div>
      <div class="item">${ic('search')}</div><div class="item on">${ic('home')}</div><div class="item">${ic('download')}</div><div class="item">${ic('bookmark')}</div>
      <div class="sep"></div>${libItems}<div class="item bottom">${ic('settings')}</div></nav>
    <div class="status"><span class="clock">8:41 PM</span>${ic('refresh')}${ic('people')}${ic('phone')}</div>
    <div class="body">
      <div class="greet" data-region="greet" style="top:64px">Settling in for the evening, ${o.name ?? 'Sam'}?</div>
      <section class="region" data-region="cw" style="top:168px"><h3 class="h-section">Continue Watching</h3><div class="track">
        ${[['w-holiday', 'Holiday Touchdown', '52min left', 42], ['w-got2', 'Game of Thrones', 'S5 E1 · The Wars To Come', 55], ['w-crystal', 'Crystal Lake', 'S1 E2', 8], ['w-meg', 'The Meg', '1h 12min left', 30], ['w-topgear', 'Top Gear', 'S22 E3', 70]]
          .map(([a, t, s, p]) => `<div class="wcard"><div class="art"><img src="${A(a)}"><div class="progress"><i style="width:${p}%"></i></div></div><div class="t">${t}</div><div class="s">${s}</div></div>`).join('')}
      </div></section>
      <section class="region" data-region="networks" style="top:562px"><h3 class="h-section">Networks</h3><div class="track net-track">
        ${nets.map((n) => ntile(n, (all.find((x) => x[0] === n) || [0, 0])[1])).join('')}
      </div></section>
      <section class="region" data-region="genres" style="top:814px"><h3 class="h-section">Genres</h3><div class="track gen-track">
        ${gens.map((g) => `<div class="gtile"><img src="${A(GENRE_ART[g] || 's-paradise')}"><span>${g}</span></div>`).join('')}
      </div></section>
    </div></div>`;
}

// ---------- Scripted remote ----------
const Q = new URLSearchParams(location.search);
const RAW = Q.has('raw'), REC = Q.has('rec');
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const $ = (s, r = document) => (typeof s === 'string' ? r.querySelector(s) : s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
let current = null;
let hudTimer;
function hud(k) {
  const h = $('#hud');
  const label = { left: ic('left'), right: ic('right'), up: ic('up'), down: ic('down'), ok: 'OK', back: ic('back') }[k] ?? k;
  h.innerHTML = `<span class="k">${label}</span>`;
  h.classList.add('show');
  clearTimeout(hudTimer);
  hudTimer = setTimeout(() => h.classList.remove('show'), 420);
}
function focus(el) {
  el = $(el);
  if (current) current.classList.remove('f');
  if (el) el.classList.add('f');
  current = el;
}
async function move(dir, el, dwell = 420) { hud(dir); focus(el); await wait(dwell); }
async function press(el, fn, dwell = 380) {
  el = $(el ?? current);
  hud('ok');
  el?.classList.add('press');
  await wait(130);
  el?.classList.remove('press');
  fn?.(el);
  await wait(dwell);
}
async function typeInto(el, text, ms = 75) {
  el = $(el);
  const v = el.querySelector('.val');
  for (const ch of text) { v.textContent += ch; await wait(ms + Math.random() * 50); }
}
function show(id) { $$('.scene').forEach((s) => s.classList.toggle('on', s.id === id)); }

window.addEventListener('DOMContentLoaded', () => {
  const sym = Object.entries(ICONS).map(([k, v]) =>
    `<symbol id="i-${k}" viewBox="0 0 24 24">${v.replace(/class="f"/g, 'fill="currentColor" stroke="none"')}</symbol>`).join('');
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute">${sym}</svg>`);
  const screen = $('.screen');
  screen.insertAdjacentHTML('beforeend', '<div id="hud"></div>');
  if (!RAW) {
    const fit = () => { const k = Math.min(innerWidth / 1920, innerHeight / 1080, 1); screen.style.transform = `scale(${k})`; };
    document.body.classList.add('fit'); fit(); addEventListener('resize', fit);
  }
  window.BUILD?.();
  document.fonts.ready.then(async () => {
    await Promise.all($$('img').map((i) => (i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; }))));
    await wait(REC ? 900 : 300);
    await window.SCRIPT();
    window.__done = true;
    if (!REC) { await wait(3500); location.reload(); }
  });
});
