import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    class _PlainOutput:
        def _mime_(self):
            return ("text/plain", "native text fixture")

    _PlainOutput()
    return


@app.cell
def _():
    class _JSONOutput:
        def _mime_(self):
            return ("application/json", '{"answer": 42, "ready": true}')

    _JSONOutput()
    return


@app.cell
def _():
    class _TracebackOutput:
        def _mime_(self):
            return (
                "application/vnd.marimo+traceback",
                'Traceback\n  File "/tmp/native_outputs.py", line 7\nValueError',
            )

    _TracebackOutput()
    return


@app.cell
def _():
    class _CSVOutput:
        def _mime_(self):
            return ("text/csv", 'name,value\n"alpha,beta",2\ngamma,3\n')

    _CSVOutput()
    return


@app.cell
def _():
    class _PNGOutput:
        def _mime_(self):
            return (
                "image/png",
                "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
                "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
            )

    _PNGOutput()
    return


@app.cell
def _():
    class _UnsupportedOutput:
        def _mime_(self):
            return ("text/html", "<strong>recoverable raw fixture</strong>")

    _UnsupportedOutput()
    return


if __name__ == "__main__":
    app.run()
