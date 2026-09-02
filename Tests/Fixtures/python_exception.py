import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    raise RuntimeError("fixture exception")
    return


if __name__ == "__main__":
    app.run()
