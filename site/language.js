const englishCopy = {
  "title": [
    "Lunamo — A Python notebook editor for Mac"
  ],
  "meta[name=description] @content": [
    "Edit Python notebooks in Lunamo’s native Mac interface."
  ],
  "nav @aria-label": [
    "Main navigation"
  ],
  "#appearance @aria-label": [
    "Page appearance"
  ],
  "#appearance option": [
    "Auto",
    "Light",
    "Dark"
  ],
  ".intro": [
    "A Python notebook editor built with SwiftUI.<br/>Edit and run <a class=\"marimo-link\" href=\"https://marimo.io/\">marimo</a> notebooks on your Mac."
  ],
  ".download span": [
    "Download for Mac"
  ],
  ".spec": [
    "Apple Silicon <span>·</span> macOS 26 or later"
  ],
  ".source": [
    "Source code <span aria-hidden=\"true\">↗</span>"
  ],
  ".tour @aria-label": [
    "Notebook workspace"
  ],
  ".mac-menus span:not(.apple-mark)": [
    "File",
    "Edit",
    "View",
    "Notebook",
    "Export",
    "Window",
    "Help"
  ],
  ".switcher @aria-label": [
    "Preview panels"
  ],
  ".switcher button": [
    "Files",
    "Notebook",
    "Terminal"
  ],
  ".scenes h2": [
    "Files",
    "Notebook",
    "Terminal"
  ],
  ".scenes p": [
    "The sidebar lists the notebooks in your folder. Select one to open it in the same window.",
    "Each cell shows its results right below the code. Hide the sidebar to give both the full width of the window.",
    "Open a terminal below your notebook to run shell commands while keeping your code and results in view."
  ],
  ".features h2": [
    "Features"
  ],
  ".features h3": [
    "Japanese text input",
    "Built-in Python",
    "Import Jupyter notebooks",
    "On-device assistant"
  ],
  ".features p": [
    "The editor uses native AppKit text input, so refreshing the notebook doesn’t interrupt Japanese text composition.",
    "Python and <a class=\"marimo-link\" href=\"https://marimo.io/\">marimo</a> come with the app. Install additional packages in Settings.",
    "Open an .ipynb file to convert it to a <a class=\"marimo-link\" href=\"https://marimo.io/\">marimo</a> notebook. The original stays intact.",
    "On Macs that support Apple Intelligence, select code to get an explanation or a suggested edit inside Lunamo."
  ],
  ".editor h2": [
    "Editor settings"
  ],
  ".editor p": [
    "Press <kbd>⌘</kbd> <kbd>Return</kbd> to run a cell or <kbd>Shift</kbd> <kbd>Return</kbd> to advance to the next one. Customize the shortcuts and text size in Settings."
  ],
  "#settings-shot @alt": [
    "Lunamo settings showing customizable shortcuts for running and navigating cells."
  ],
  ".project-links @aria-label": [
    "Releases, feedback, and developer"
  ],
  ".project-links h2": [
    "Releases",
    "Bugs and feature requests",
    "Follow the developer"
  ],
  ".project-links p": [
    "Read the release notes and download the DMG for each version.",
    "Report a problem or suggest a feature for Lunamo.",
    "Find <a href=\"https://mani1261790.github.io/\" rel=\"author\">Mani</a>, the developer of Lunamo, on X and GitHub."
  ],
  ".project-links article > a": [
    "View releases ↗",
    "Open a GitHub issue ↗"
  ],
  ".profile-links a": [
    "X (Twitter)↗",
    "GitHub ↗"
  ]
};

// The Japanese copy lives in the markup and works without JavaScript.
// Only shipped translations contain markup (links, key caps, and line breaks).
const fields = Object.entries(englishCopy).flatMap(([key, translations]) => {
  const [selector, attribute] = key.split(' @');
  return Array.from(document.querySelectorAll(selector), (element, i) => ({
    element, attribute, en: translations[i],
    ja: attribute ? element.getAttribute(attribute) : element.innerHTML
  }));
});
const languageButton = document.querySelector('button.language');
const validLanguage = value => value === 'ja' || value === 'en';
function browserLanguage() {
  return (navigator.languages?.length ? navigator.languages : [navigator.language])
    .map(tag => tag.split('-')[0].toLowerCase()).find(validLanguage) || 'en';
}
function displayLanguage(language) {
  document.documentElement.lang = language;
  for (const field of fields) {
    if (field.attribute) field.element.setAttribute(field.attribute, field[language]);
    else field.element.innerHTML = field[language];
  }
  for (const [property,value] of Object.entries({
    title: document.title,
    description: document.querySelector('meta[name="description"]').content,
    'image:alt': language === 'ja'
      ? '三日月のアプリアイコンと「Lunamo」のロゴ。'
      : 'The crescent app icon and Lunamo wordmark.'
  })) {
    document.querySelector('meta[property="og:'+property+'"]').content = value;
    document.querySelector('meta[name="twitter:'+property+'"]').content = value;
  }
  document.querySelector('meta[property="og:locale"]').content = language === 'ja' ? 'ja_JP' : 'en_US';
  languageButton.lang = language === 'ja' ? 'en' : 'ja';
  languageButton.textContent = language === 'ja' ? 'English' : '日本語';
  languageButton.hidden = false;
  document.dispatchEvent(new Event('lunamo-language'));
}
let savedLanguage;
try { savedLanguage = localStorage.getItem('lunamo-language'); } catch {}
const pageURL = new URL(location.href);
const requestedLanguage = pageURL.searchParams.get('lang');
let languageChoice = validLanguage(requestedLanguage) ? requestedLanguage : savedLanguage;
function rememberLanguage(language) {
  languageChoice = language;
  try { localStorage.setItem('lunamo-language', language); } catch {}
}
if (validLanguage(requestedLanguage)) {
  rememberLanguage(requestedLanguage);
  pageURL.searchParams.delete('lang');
  history.replaceState(history.state, '', pageURL);
}
displayLanguage(validLanguage(languageChoice) ? languageChoice : browserLanguage());
languageButton.addEventListener('click', () => {
  rememberLanguage(languageButton.lang);
  displayLanguage(languageChoice);
});
addEventListener('languagechange', () => {
  if (!validLanguage(languageChoice)) displayLanguage(browserLanguage());
});
