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
function alignIntro() {
  // Measure the untransformed destination, never the animated screenshot.
  const target = slot.getBoundingClientRect();
  const tourTop = tour.getBoundingClientRect().top;
  const pinTop = parseFloat(getComputedStyle(figure).top) || 80;
  const distance = Math.max(1, scrollY + tourTop - pinTop);
  const t = reduce.matches ? 1 : Math.min(1, Math.max(0, scrollY / distance));
  const landed = t * t * (3 - 2 * t);
  const remaining = 1 - landed;
  const viewport = document.documentElement.clientWidth;
  const openingWidth = viewport >= 960
    ? Math.min(viewport * .8, 1152)
    : Math.min(viewport * .94, target.width * 1.15);
  const openingScale = Math.max(1, openingWidth / Math.max(1, target.width));
  const centerOffset = (viewport - target.width) / 2 - target.left;
  tour.style.setProperty('--intro-x', (centerOffset * remaining) + 'px');
  tour.style.setProperty('--intro-scale', 1 + remaining * (openingScale - 1));
  tour.style.setProperty('--shell-y', (remaining * 54) + 'px');
  tour.style.setProperty('--shell-opacity', landed);
  tour.style.setProperty('--copy-opacity', Math.max(0, (landed - .45) / .55));
}
let frame=0;
function update(){
  frame=0;
  const stacked = innerWidth < 960 && innerHeight >= 630 && figure.clientWidth * .6 + 270 < innerHeight;
  const follows=(wide.matches || stacked) && !reduce.matches;
  switcher.hidden=follows;
  tour.classList.toggle('following',follows);
  alignIntro();
  if(follows){
    const y=stacked ? Math.max(innerHeight*.68, figure.getBoundingClientRect().bottom+90) : innerHeight*.53;
    const scene=scenes.reduce((best,el)=>{
      const gap=r=>Math.abs(r.top+r.height/2-y);
      return gap(el.getBoundingClientRect())<gap(best.getBoundingClientRect())?el:best;
    },scenes[0]);
    if(scene.dataset.scene!==active)choose(scene.dataset.scene);
  }

}
const schedule=()=>{if(!frame)frame=requestAnimationFrame(update)};
for(const e of ['scroll','resize'])addEventListener(e,schedule,{passive:true});
for(const q of [wide,reduce])q.addEventListener('change',schedule);
document.addEventListener('lunamo-language',()=>{draw();schedule()});
draw();update();document.fonts.ready.then(schedule);
