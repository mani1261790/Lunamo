import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    value = "edit this file externally while the document is dirty"
    value
    return


if __name__ == "__main__":
    app.run()
