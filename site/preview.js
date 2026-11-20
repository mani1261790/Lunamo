const appearance = document.querySelector('#appearance');
const system = matchMedia('(prefers-color-scheme: dark)');
const wide = matchMedia('(min-width: 960px) and (min-height: 630px)');
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const figure = document.querySelector('.showcase');
const switcher = document.querySelector('.switcher');
const tour = document.querySelector('.tour');
const buttons = [...document.querySelectorAll('[data-view]')];
const scenes = [...document.querySelectorAll('[data-scene]')];
const notebook = document.querySelector('#notebook');
const settings = document.querySelector('#settings-shot');
let active = 'open';
let lastPath = '';
const alt = {en: {
  open: 'A moon observation notebook with a file sidebar, Python code, and its results.',
  closed: 'The notebook with its sidebar hidden, showing moon brightness by day.',
  terminal: 'The notebook with the built-in terminal open below it.'
}, ja: {
  open: '月の観測ノート。左にファイル一覧、右に月の明るさを求めるコードと計算結果。',
  closed: 'サイドバーを閉じた編集画面。日ごとの月の明るさが棒で並ぶ。',
  terminal: 'ノートの下に内蔵ターミナルを開いた編集画面。'
}};
function draw(){
  const value = document.querySelector('.appearance-value');
  value.textContent = appearance.selectedOptions[0].textContent;
  value.hidden = false;
  const theme = appearance.value === 'auto' ? (system.matches ? 'dark' : 'light') : appearance.value;
  if(appearance.value==='auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme=theme;
  const device = document.querySelector('.device-frame');
  const devicePath = 'assets/lunamo-laptop-' + theme + '-v2.png';
  if(device.getAttribute('src') !== devicePath) device.src = devicePath;
  const menus = document.documentElement.lang === 'en' ? {file:'File',edit:'Edit',view:'View',notebook:'Notebook',window:'Window',help:'Help'} : {file:'ファイル',edit:'編集',view:'表示',notebook:'ノートブック',window:'ウインドウ',help:'ヘルプ'};
  document.querySelectorAll('[data-menu]').forEach(el=>{el.textContent=menus[el.dataset.menu]});
  const icon = theme === 'dark' ? 'assets/lunamo-night.png' : 'assets/lunamo.png';
  document.querySelectorAll('.appicon,.brand img').forEach(img=>{if(img.getAttribute('src')!==icon)img.src=icon});
  const atlas = document.documentElement.lang === 'en' ? 'assets/atlas-en-' : 'assets/atlas-';
  const path=atlas+theme+'-'+active+'.webp';
  if(path!==lastPath){
    notebook.src=path;
    lastPath=path;
  }
  notebook.alt=alt[document.documentElement.lang][active];
  const sett=atlas+theme+'-settings.webp';
  if(settings.getAttribute('src')!==sett)settings.src=sett;
  buttons.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.view===active)));
  scenes.forEach(a=>a.classList.toggle('current',a.dataset.scene===active));
  document.querySelector('.desktop').classList.toggle('night',theme==='dark');
}
function choose(view){active=view;draw()}
appearance.value=document.documentElement.dataset.theme||'auto';
appearance.addEventListener('change',()=>{
  try{localStorage.setItem('lunamo-appearance',appearance.value)}catch{}
  draw();
});
system.addEventListener('change',draw);
buttons.forEach(b=>b.addEventListener('click',()=>choose(b.dataset.view)));
const slot = tour.querySelector('.screen-slot');
let geometry;
let needsMeasure = true;
let lastIntro = -1;
let frame = 0;
function measure() {
  const stacked = innerWidth < 960 && innerHeight >= 630 && figure.clientWidth * .6 + 270 < innerHeight;
  const follows = (wide.matches || stacked) && !reduce.matches;
  switcher.hidden = follows;
  tour.classList.toggle('following', follows);
  const headerBottom = document.querySelector('header').getBoundingClientRect().bottom;
  const viewport = window.visualViewport;
  const usableTop = Math.max(headerBottom, viewport?.offsetTop || 0);
  const viewportBottom = (viewport?.offsetTop || 0) + (viewport?.height || innerHeight);
  const figureHeight = figure.offsetHeight;
  const center = (usableTop + viewportBottom) / 2;
  if (wide.matches && follows) {
    const pinTop = Math.max(usableTop + 12, center - figureHeight / 2);
    const last = scenes.at(-1).getBoundingClientRect();
    const tourTop = tour.getBoundingClientRect().top;
    figure.style.setProperty('--preview-pin-top', pinTop + 'px');
    // End the sticky containing block at the final explanation + half the Mac.
    // Native sticky scrolling now releases it; scroll events never change top.
    tour.style.setProperty('--tour-height',
      Math.max(figureHeight, last.top + last.height / 2 - tourTop + figureHeight / 2) + 'px');
  } else {
    figure.style.removeProperty('--preview-pin-top');
    tour.style.removeProperty('--tour-height');
  }
  const target = slot.getBoundingClientRect();
  const pinTop = parseFloat(getComputedStyle(figure).top) || 80;
  const viewportWidth = document.documentElement.clientWidth;
  const openingWidth = viewportWidth >= 960
    ? Math.min(viewportWidth * .8, 1152)
    : Math.min(viewportWidth * .94, target.width * 1.15);
  geometry = {
    follows, stacked, center,
    distance: Math.max(1, scrollY + tour.getBoundingClientRect().top - pinTop),
    scale: Math.max(1, openingWidth / Math.max(1, target.width)),
    x: (viewportWidth - target.width) / 2 - target.left,
    sceneY: stacked ? Math.max(innerHeight * .68, pinTop + figureHeight + 90) : center,
    scenes: scenes.map(el => {
      const r = el.getBoundingClientRect();
      return {el, center: scrollY + r.top + r.height / 2};
    })
  };
  lastIntro = -1;
  needsMeasure = false;
}
function update() {
  frame = 0;
  if (needsMeasure) measure();
  const y = scrollY;
  const t = reduce.matches ? 1 : Math.min(1, Math.max(0, y / geometry.distance));
  // Once docked, no animation styles or layout properties are touched on scroll.
  if (t !== lastIntro) {
    const landed = t * t * (3 - 2 * t);
    const remaining = 1 - landed;
    tour.style.setProperty('--intro-x', geometry.x * remaining + 'px');
    tour.style.setProperty('--intro-scale', 1 + remaining * (geometry.scale - 1));
    tour.style.setProperty('--shell-y', remaining * 54 + 'px');
    tour.style.setProperty('--shell-opacity', landed);
    tour.style.setProperty('--copy-opacity', Math.max(0, (landed - .45) / .55));
    lastIntro = t;
  }
  if (geometry.follows) {
    const focus = y + geometry.sceneY;
    const scene = geometry.scenes.reduce((best, item) =>
      Math.abs(item.center - focus) < Math.abs(best.center - focus) ? item : best);
    if (scene.el.dataset.scene !== active) choose(scene.el.dataset.scene);
  }
}
const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
const invalidate = () => { needsMeasure = true; schedule(); };
addEventListener('scroll', schedule, {passive:true});
addEventListener('resize', invalidate, {passive:true});
window.visualViewport?.addEventListener('resize', invalidate, {passive:true});
for (const q of [wide, reduce]) q.addEventListener('change', invalidate);
document.addEventListener('lunamo-language', () => { draw(); invalidate(); });
draw(); update(); document.fonts.ready.then(invalidate);
