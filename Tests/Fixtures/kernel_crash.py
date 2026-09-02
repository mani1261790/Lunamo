import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import os
    os._exit(17)
    return


if __name__ == "__main__":
    app.run()
