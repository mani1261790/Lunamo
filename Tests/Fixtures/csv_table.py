import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import csv
    import io
    rows = list(csv.DictReader(io.StringIO("name,value\nalpha,1\nbeta,2\n")))
    rows
    return


if __name__ == "__main__":
    app.run()
