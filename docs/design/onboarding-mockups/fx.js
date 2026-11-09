// Motion helpers for directions 6–8 (load after shared.js). All coordinates are in 1920×1080 screen space.
const SPRING = 'linear(0, 0.0063, 0.0251 1.6%, 0.1004 3.3%, 0.3943 7.3%, 0.5994 10.1%, 0.7616 12.9%, 0.8822 15.8%, 0.9673 18.8%, 1.0225 21.9%, 1.0546 25.2%, 1.0695 28.8%, 1.0717 32.7%, 1.0636 37.3%, 1.0284 47.4%, 1.0076 56.6%, 0.9977 67.6%, 0.9982 82.5%, 1)';
const BOUNCE = 'cubic-bezier(0.34, 1.56, 0.64, 1)';
const OUT = 'cubic-bezier(0.16, 1, 0.3, 1)';
const IN = 'cubic-bezier(0.7, 0, 0.84, 0)';

function screenK() { const s = $('.screen').getBoundingClientRect(); return { s, k: s.width / 1920 }; }
function rectOf(el) {
  const { s, k } = screenK(); const r = $(el).getBoundingClientRect();
  return { x: (r.left - s.left) / k, y: (r.top - s.top) / k, w: r.width / k, h: r.height / k };
}

// Headline words rise out of a mask; outWords lifts and blurs them away.
function splitWords(el) {
  el = $(el); if (el.dataset.split) return el; el.dataset.split = 1;
  el.innerHTML = el.textContent.trim().split(/\s+/).map((w) => `<span class="wd"><span class="wi">${w}</span></span>`).join(' ');
  return el;
}
function inWords(el, delay = 0, stagger = 70) {
  el = splitWords(el);
  return Promise.all($$('.wi', el).map((w, i) => w.animate(
    [{ transform: 'translateY(110%) rotate(7deg)', opacity: 0 }, { transform: 'none', opacity: 1 }],
    { duration: 950, delay: delay + i * stagger, easing: OUT, fill: 'both' }).finished));
}
function outWords(el, stagger = 35) {
  el = splitWords(el);
  return Promise.all($$('.wi', el).map((w, i) => w.animate(
    [{ transform: 'none', opacity: 1, filter: 'blur(0px)' }, { transform: 'translateY(-70%)', opacity: 0, filter: 'blur(10px)' }],
    { duration: 420, delay: i * stagger, easing: IN, fill: 'both' }).finished));
}

// A clone at the target's size travels from `from` to `to` along an arc, scaling uniformly.
function fly(from, to, { html, dur = 820, arc = -110, cls = '' } = {}) {
  const a = rectOf(from), b = rectOf(to);
  const c = document.createElement('div');
  c.className = 'flyer ' + cls;
  c.innerHTML = html ?? $(from).outerHTML.replace(/\s(f|press|on)(?=[\s"])/g, '');
  Object.assign(c.style, { left: b.x + 'px', top: b.y + 'px', width: b.w + 'px', height: b.h + 'px' });
  $('.screen').append(c);
  const s0 = Math.min(a.w / b.w, a.h / b.h);
  const dx = a.x + a.w / 2 - (b.x + b.w / 2), dy = a.y + a.h / 2 - (b.y + b.h / 2);
  const anim = c.animate([
    { transform: `translate(${dx}px, ${dy}px) scale(${s0})`, opacity: 1 },
    { transform: `translate(${dx / 2}px, ${dy / 2 + arc}px) scale(${(s0 + 1) / 2 * 1.08}) rotate(-4deg)`, offset: 0.5 },
    { transform: 'none', opacity: 1 }], { duration: dur, easing: OUT });
  return anim.finished.then(() => c.remove());
}

// FLIP: animate elements from where they were before `mutate` to where they are after.
function flip(els, mutate, dur = 700) {
  const before = new Map(els.map((e) => [e, rectOf(e)]));
  mutate();
  els.forEach((e) => {
    if (!e.isConnected) return;
    const b = before.get(e), a = rectOf(e), dx = b.x - a.x, dy = b.y - a.y;
    if (Math.abs(dx) + Math.abs(dy) > 0.5) e.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: 'none' }], { duration: dur, easing: SPRING });
  });
}

function countUp(el, to, ms = 1600, fmt = (n) => n.toLocaleString('en-US')) {
  el = $(el); const t0 = performance.now();
  return new Promise((res) => {
    const tick = (t) => { const p = Math.min(1, (t - t0) / ms), e = 1 - Math.pow(1 - p, 4); el.textContent = fmt(Math.round(to * e)); p < 1 ? requestAnimationFrame(tick) : res(); };
    requestAnimationFrame(tick);
  });
}

// Split-flap: each character flips down into place.
function splitFlap(el, text, stagger = 70) {
  el = $(el);
  el.innerHTML = [...text].map((ch) => `<span class="flap">${ch === ' ' ? '&nbsp;' : ch}</span>`).join('');
  return Promise.all($$('.flap', el).map((f, i) => f.animate(
    [{ transform: 'perspective(600px) rotateX(-95deg)', opacity: 0 }, { transform: 'perspective(600px) rotateX(12deg)', opacity: 1, offset: 0.7 }, { transform: 'none', opacity: 1 }],
    { duration: 700, delay: i * stagger, easing: OUT, fill: 'both' }).finished));
}

// Slot-machine reels: each character spins through random glyphs and lands, left to right.
function reels(el, text, { spins = 14, stagger = 140, dur = 1300 } = {}) {
  el = $(el);
  const pool = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  el.innerHTML = [...text].map((ch) => {
    if (ch === '-' || ch === '‑') return `<span class="reel dash">${ch}</span>`;
    const strip = Array.from({ length: spins }, () => pool[Math.floor(Math.random() * pool.length)]).concat(ch);
    return `<span class="reel"><span class="strip">${strip.map((c) => `<span>${c}</span>`).join('')}</span></span>`;
  }).join('');
  return Promise.all($$('.strip', el).map((s, i) => s.animate(
    [{ transform: 'translateY(0)', filter: 'blur(3px)' }, { transform: `translateY(calc(${-spins}em - 0.08em))`, filter: 'blur(0px)', offset: 0.85 }, { transform: `translateY(${-spins}em)` }],
    { duration: dur + i * stagger, easing: 'cubic-bezier(0.25, 0.9, 0.3, 1)', fill: 'both' }).finished));
}

// A light band sweeps across an element (used on success).
function shine(el) {
  el = $(el); const s = document.createElement('i'); s.className = 'shine'; el.append(s);
  return s.animate([{ transform: 'translateX(-120%) skewX(-20deg)' }, { transform: 'translateX(320%) skewX(-20deg)' }], { duration: 1100, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' }).finished.then(() => s.remove());
}

// A ring expands out of an element (used on select).
function ripple(el) {
  el = $(el); const r = document.createElement('i'); r.className = 'ripple'; el.append(r);
  return r.animate([{ transform: 'scale(0.6)', opacity: 0.9 }, { transform: 'scale(1.5)', opacity: 0 }], { duration: 700, easing: OUT }).finished.then(() => r.remove());
}

function pulse(el, scale = 1.12) {
  return $(el).animate([{ transform: 'scale(1)' }, { transform: `scale(${scale})` }, { transform: 'scale(1)' }], { duration: 520, easing: BOUNCE });
}
