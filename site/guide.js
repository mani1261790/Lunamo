const appearance = document.querySelector('#appearance');
try { appearance.value = localStorage.getItem('lunamo-appearance') || 'auto'; } catch {}
function drawAppearance() {
  const value = document.querySelector('.appearance-value');
  value.textContent = appearance.selectedOptions[0].textContent;
  value.hidden = false;
  if (appearance.value === 'auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = appearance.value;
}
appearance.addEventListener('change', () => {
  try { localStorage.setItem('lunamo-appearance', appearance.value); } catch {}
  drawAppearance();
});
document.addEventListener('lunamo-language', drawAppearance);
drawAppearance();
