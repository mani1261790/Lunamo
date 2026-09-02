import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import sys
    print("stdout fixture")
    print("stderr fixture", file=sys.stderr)
    return


if __name__ == "__main__":
    app.run()
