import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import marimo as mo
    slider = mo.ui.slider(start=0, stop=10, value=2)
    slider
    return (slider,)


@app.cell
def _(slider):
    doubled = slider.value * 2
    doubled
    return


if __name__ == "__main__":
    app.run()
