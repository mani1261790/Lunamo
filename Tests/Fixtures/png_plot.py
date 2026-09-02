import marimo

__generated_with = "0.24.0"
app = marimo.App()


@app.cell
def _():
    import matplotlib.pyplot as plt
    figure, axis = plt.subplots()
    axis.plot([1, 2, 3], [1, 4, 9])
    figure
    return


if __name__ == "__main__":
    app.run()
