import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    "Run with the test Python environment that reports a non-0.24.0 marimo version."
    return


if __name__ == "__main__":
    app.run()
