// Shared icon sprite, side rail and fit-to-window scaling for the Watchlist mockups.
const ICONS = {
  search: '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/>',
  home: '<path class="f" d="M4 10.4 12 3.8l8 6.6V20h-5.2v-5.6H9.2V20H4z"/>',
  download: '<path d="M12 4v10M7.5 9.6 12 14l4.5-4.4M5 19.5h14"/>',
  movie: '<rect x="3" y="6" width="18" height="13.5" rx="1.6"/><path d="M3 10.5h18M7.5 6l2 4.5M12.5 6l2 4.5M17.5 6l2 4.5"/>',
  tv: '<rect x="3" y="4.5" width="18" height="13" rx="1.6"/><path d="M8.5 20.5h7"/>',
  bookmark: '<path d="M6.8 3.8h10.4c.4 0 .8.4.8.8v15.6l-6-3.9-6 3.9V4.6c0-.4.4-.8.8-.8z"/>',
  bookmarkf: '<path class="f" d="M6.8 3.8h10.4c.4 0 .8.4.8.8v15.6l-6-3.9-6 3.9V4.6c0-.4.4-.8.8-.8z"/>',
  heart: '<path d="M12 19.6s-7.5-4.6-7.5-10.1A4.1 4.1 0 0 1 12 7.2a4.1 4.1 0 0 1 7.5 2.3c0 5.5-7.5 10.1-7.5 10.1z"/>',
  heartf: '<path class="f" d="M12 19.6s-7.5-4.6-7.5-10.1A4.1 4.1 0 0 1 12 7.2a4.1 4.1 0 0 1 7.5 2.3c0 5.5-7.5 10.1-7.5 10.1z"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2.8l1.6 2.3 2.7-.6.9 2.6 2.6.9-.6 2.7 2.3 1.6-2.3 1.6.6 2.7-2.6.9-.9 2.6-2.7-.6L12 21.2l-1.6-2.3-2.7.6-.9-2.6-2.6-.9.6-2.7L2.5 12l2.3-1.6-.6-2.7 2.6-.9.9-2.6 2.7.6z"/>',
  refresh: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4v5h-5"/>',
  people: '<circle cx="9" cy="8.2" r="3.4"/><path d="M2.8 19.5c.3-3.4 2.9-5.6 6.2-5.6s5.9 2.2 6.2 5.6zM15.4 4.9a3.4 3.4 0 0 1 0 6.6M17.6 14.2c2 .7 3.3 2.6 3.6 5.3"/>',
  phone: '<rect x="7" y="2.5" width="10" height="19" rx="2"/><path d="M11.2 18.2h1.6"/>',
  play: '<path class="f" d="M8 5.2v13.6L18.6 12z"/>',
  resume: '<path d="M6 5.5v13"/><path class="f" d="M10 5.2v13.6L20 12z"/>',
  check: '<path d="M5 12.6l4.4 4.4L19 7.4"/>',
  more: '<circle class="f" cx="12" cy="5.5" r="1.6"/><circle class="f" cx="12" cy="12" r="1.6"/><circle class="f" cx="12" cy="18.5" r="1.6"/>',
  sort: '<path d="M4 7h16M7 12h10M10 17h4"/>',
  filter: '<path d="M4 6h16l-6.2 7.2V19l-3.6-1.8v-4z"/>',
  close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  left: '<path d="M14.5 6 8.5 12l6 6"/>',
  right: '<path d="M9.5 6l6 6-6 6"/>',
  up: '<path d="M6 14.5l6-6 6 6"/>',
  down: '<path d="M6 9.5l6 6 6-6"/>',
  updown: '<path d="M8 9l4-4 4 4M8 15l4 4 4-4"/>',
  drag: '<path d="M5 9h14M5 15h14"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.6v.2"/>',
  add: '<path d="M12 5v14M5 12h14"/>',
  star: '<path d="M12 3.8l2.5 5.2 5.7.7-4.2 3.9 1.1 5.6L12 16.4l-5.1 2.8L8 13.6 3.8 9.7l5.7-.7z"/>',
  restart: '<path d="M5 12a7 7 0 1 0 2.1-5M5 4v4h4"/>',
  newep: '<circle class="f" cx="12" cy="12" r="4"/>',
  grid: '<rect x="4" y="4" width="6.5" height="6.5" rx="1.2"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.2"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.2"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.2"/>',
  rows: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  shuffle: '<path d="M16 4h4v4M4 20 20 4M16 20h4v-4M14.5 14.5 20 20M4 4l5 5"/>',
};

(function () {
  const sym = Object.entries(ICONS).map(([k, v]) =>
    `<symbol id="i-${k}" viewBox="0 0 24 24">${v.replace(/class="f"/g, 'fill="currentColor" stroke="none"')}</symbol>`).join('');
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute">${sym}</svg>`);

  window.ic = (n, cls = '') => `<svg class="i ${cls}"><use href="#i-${n}"/></svg>`;

  // Hydrate <i data-i="name"> placeholders.
  document.querySelectorAll('[data-i]').forEach((el) => { el.outerHTML = ic(el.dataset.i, el.className); });

  // Side rail: same order as the shipped rail, with Watchlist inserted after Downloads.
  document.querySelectorAll('.rail[data-build]').forEach((rail) => {
    const lib = '<div class="item lib">' + ic('movie') + '</div>';
    rail.innerHTML =
      '<div class="avatar">S</div>' +
      '<div class="item">' + ic('search') + '</div>' +
      '<div class="item">' + ic('home') + '</div>' +
      '<div class="item">' + ic('download') + '</div>' +
      '<div class="item on">' + ic('bookmarkf') + '</div>' +
      '<div class="sep"></div>' + lib + lib + lib + lib + '<div class="item lib">' + ic('tv') + '</div>' +
      '<div class="item bottom">' + ic('settings') + '</div>';
  });

  const status = document.querySelector('.status[data-build]');
  if (status) status.innerHTML = '<span class="clock">8:41 PM</span>' + ic('refresh') + ic('people') + ic('phone');

  // Fit the 1920×1080 frame into the window unless ?raw is set (used for screenshots).
  if (!location.search.includes('raw')) {
    const s = document.querySelector('.screen');
    const fit = () => { const k = Math.min(innerWidth / 1920, innerHeight / 1080, 1); s.style.transform = `scale(${k})`; };
    document.body.classList.add('fit'); fit(); addEventListener('resize', fit);
  }
})();
