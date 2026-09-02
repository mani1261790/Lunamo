(() => {
  const target = document.getElementById("vega-output");
  const source = new TextDecoder().decode(Uint8Array.from(atob(target.dataset.source), c => c.charCodeAt(0)));
  const spec = JSON.parse(source);
  vegaEmbed(target, spec, { actions: false, renderer: "svg" }).catch(error => {
    target.textContent = `Vega rendering failed: ${error}`;
  });
})();
