const controls = document.querySelector('.controls');
const sidebar = document.querySelector('#sidebar');
const notebook = document.querySelector('#notebook');
const modes = [...document.querySelectorAll('[name=mode]')];
const systemDark = matchMedia('(prefers-color-scheme: dark)');
let override = false;

function render() {
  const dark = modes[1].checked;
  const open = sidebar.getAttribute('aria-pressed') === 'true';
  const path = 'assets/window-' + (dark ? 'dark' : 'light') + '-' + (open ? 'open' : 'closed') + '.webp';
  notebook.src = notebook.parentElement.href = path;
  notebook.alt = open ? '月の観測ノート。左にファイル一覧、右にPythonのコードと実行結果。' : 'サイドバーを閉じ、ウィンドウの幅いっぱいに月の観測ノートを表示。';
  document.querySelector('.desktop').classList.toggle('night', dark);
}
function followSystem() {
  if (!override) { modes[systemDark.matches ? 1 : 0].checked = true; render(); }
}
sidebar.addEventListener('click', () => {
  sidebar.setAttribute('aria-pressed', String(sidebar.getAttribute('aria-pressed') !== 'true'));
  render();
});
controls.addEventListener('change', () => { override = true; render(); });
systemDark.addEventListener('change', followSystem);
followSystem();
controls.hidden = false;

// Keep the screenshot legible first; reveal the Mac as the reader reaches it.
const stage = document.querySelector('.machine');
const motion = matchMedia('(min-width: 701px) and (prefers-reduced-motion: no-preference)');
let frame = 0;
function positionStage() {
  frame = 0;
  const progress = motion.matches ? Math.min(1, Math.max(0, (innerHeight * .58 - stage.getBoundingClientRect().top) / (innerHeight * .43))) : 1;
  const settled = progress * progress * (3 - 2 * progress);
  stage.style.setProperty('--reveal', settled);
  stage.style.setProperty('--rise', ((1 - settled) * 58) + 'px');
  stage.style.setProperty('--zoom', 1 + .11 * (1 - settled));
}
function scheduleStage() { if (!frame) frame = requestAnimationFrame(positionStage); }
addEventListener('scroll', scheduleStage, {passive:true});
addEventListener('resize', scheduleStage);
motion.addEventListener('change', scheduleStage);
document.fonts.ready.then(scheduleStage);
positionStage();
