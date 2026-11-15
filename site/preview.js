const appearance = document.querySelector('#appearance');
const system = matchMedia('(prefers-color-scheme: dark)');
const wide = matchMedia('(min-width: 960px) and (min-height: 630px)');
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const stage = document.querySelector('.machine');
const tour = document.querySelector('.tour');
const buttons = [...document.querySelectorAll('[data-view]')];
const scenes = [...document.querySelectorAll('[data-scene]')];
const notebook = document.querySelector('#notebook');
const settings = document.querySelector('#settings-shot');
let active = 'open';
let lastPath = '';
const alt = {
  open: '月の観測ノート。左にファイル一覧、右に月の明るさを求めるコードと計算結果。',
  closed: 'サイドバーを閉じた編集画面。日ごとの月の明るさが棒で並ぶ。',
  terminal: 'ノートの下に内蔵ターミナルを開いた編集画面。'
};
function draw(){
  const theme = appearance.value === 'auto' ? (system.matches ? 'dark' : 'light') : appearance.value;
  if(appearance.value==='auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme=theme;
  const icon = theme === 'dark' ? 'assets/lunamo-night.png' : 'assets/lunamo.png';
  document.querySelectorAll('.appicon,.brand img').forEach(img=>{if(img.getAttribute('src')!==icon)img.src=icon});
  const path='assets/atlas-'+theme+'-'+active+'.webp';
  if(path!==lastPath){
    notebook.src=notebook.parentElement.href=path;
    notebook.alt=alt[active]; lastPath=path;
  }
  const sett='assets/atlas-'+theme+'-settings.webp';
  if(settings.getAttribute('src')!==sett)settings.src=settings.parentElement.href=sett;
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
buttons.forEach(b=>b.addEventListener('click',()=>{
  choose(b.dataset.view);
  if(wide.matches&&!reduce.matches){
    const a=scenes.find(x=>x.dataset.scene===active);
    window.scrollBy({top:a.getBoundingClientRect().top+a.offsetHeight/2-innerHeight*.53,behavior:'instant'});
  }
}));
let frame=0;
function update(){
  frame=0;
  const follows=wide.matches&&!reduce.matches;
  tour.classList.toggle('following',follows);
  if(follows){
    const y=innerHeight*.53;
    const scene=scenes.reduce((best,el)=>{
      const gap=r=>Math.abs(r.top+r.height/2-y);
      return gap(el.getBoundingClientRect())<gap(best.getBoundingClientRect())?el:best;
    },scenes[0]);
    if(scene.dataset.scene!==active)choose(scene.dataset.scene);
  }
  const t=follows?Math.min(1,Math.max(0,(innerHeight*.70-tour.getBoundingClientRect().top)/(innerHeight*.43))):1;
  const k=t*t*(3-2*t);
  stage.style.setProperty('--reveal',k);stage.style.setProperty('--rise',(1-k)*45+'px');stage.style.setProperty('--zoom',1+.07*(1-k));
}
const schedule=()=>{if(!frame)frame=requestAnimationFrame(update)};
for(const e of ['scroll','resize'])addEventListener(e,schedule,{passive:true});
for(const q of [wide,reduce])q.addEventListener('change',schedule);
document.querySelector('.switcher').hidden=false;
draw();update();document.fonts.ready.then(schedule);
