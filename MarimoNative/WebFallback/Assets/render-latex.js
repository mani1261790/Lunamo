(() => {
  const target = document.getElementById("math-output");
  const source = new TextDecoder().decode(Uint8Array.from(atob(target.dataset.source), c => c.charCodeAt(0)));
  katex.render(source, target, { throwOnError: false, strict: "warn", trust: false });
})();
