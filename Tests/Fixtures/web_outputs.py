import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import json as _bundle_json

    class _MIMEBundleOutput:
        def _mime_(self):
            return (
                "application/vnd.marimo+mimebundle",
                _bundle_json.dumps(
                    {
                        "text/html": "<pre><span>native bundle text</span></pre>",
                        "image/png": "data:image/png;base64,ignored-by-html",
                        "text/plain": "plain alternative",
                        "__metadata__": {
                            "text/html": {"width": 420, "height": 180}
                        },
                    }
                ),
            )

    _MIMEBundleOutput()
    return


@app.cell
def _():
    class _HTMLOutput:
        def _mime_(self):
            return ("text/html", "<strong>isolated HTML</strong>")

    _HTMLOutput()
    return


@app.cell
def _():
    class _SVGOutput:
        def _mime_(self):
            return (
                "image/svg+xml",
                "<svg xmlns='http://www.w3.org/2000/svg' width='180' height='40'>"
                "<text x='4' y='24'>safe SVG</text></svg>",
            )

    _SVGOutput()
    return


@app.cell
def _():
    class _MarkdownOutput:
        def _mime_(self):
            return ("text/markdown", "# escaped markdown\n<script>blocked</script>")

    _MarkdownOutput()
    return


@app.cell
def _():
    class _LaTeXOutput:
        def _mime_(self):
            return ("text/latex", r"x^2 + y^2 = z^2")

    _LaTeXOutput()
    return


@app.cell
def _():
    import json as _vega_json

    class _VegaOutput:
        def _mime_(self):
            return (
                "application/vnd.vegalite.v6+json",
                _vega_json.dumps(
                    {
                        "$schema": "https://vega.github.io/schema/vega-lite/v6.json",
                        "data": {"values": [{"x": "A", "y": 2}, {"x": "B", "y": 5}]},
                        "mark": "bar",
                        "encoding": {
                            "x": {"field": "x", "type": "nominal"},
                            "y": {"field": "y", "type": "quantitative"},
                        },
                    }
                ),
            )

    _VegaOutput()
    return


if __name__ == "__main__":
    app.run()
