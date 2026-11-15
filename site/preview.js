const controls = document.querySelector('.controls');
const sidebar = document.querySelector('#sidebar');
const notebook = document.querySelector('#notebook');
const modes = [...document.querySelectorAll('[name=mode]')];
const systemDark = matchMedia('(prefers-color-scheme: dark)');
let override = false;

function render() {
  const dark = modes[1].checked;
  const open = sidebar.getAttribute('aria-pressed') === 'true';
  const path = 'assets/moon-' + (dark ? 'dark' : 'light') + '-' + (open ? 'open' : 'closed') + '.png';
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
