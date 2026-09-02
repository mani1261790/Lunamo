import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import marimo as mo
    mo.Html("<strong>fixture HTML</strong>")
    return


if __name__ == "__main__":
    app.run()
