import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    first = 20
    return (first,)


@app.cell
def _(first):
    second = first + 22
    return (second,)


if __name__ == "__main__":
    app.run()
