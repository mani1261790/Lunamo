"""Contract tests for the native, non-executing notebook converter."""
import ast
import importlib.util
import json
from pathlib import Path
import unittest

from marimo._ast.parse import parse_notebook

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "native_launcher", root / "MarimoNative/Resources/Sidecar/launch_marimo_lsp.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NotebookImportTests(unittest.TestCase):
    def assert_valid_marimo(self, source):
        ast.parse(source)
        notebook = parse_notebook(source)
        self.assertIsNotNone(notebook)
        self.assertTrue(notebook.valid)

    def test_converts_jupyter_code_and_markdown_cells(self):
        source = json.dumps({
            "cells": [
                {"cell_type": "markdown", "metadata": {}, "source": ["# 日本語\n", "説明"]},
                {"cell_type": "code", "execution_count": None, "metadata": {},
                 "outputs": [], "source": ["answer = 40 + 2"]},
            ],
            "metadata": {},
            "nbformat": 4,
            "nbformat_minor": 5,
        })

        converted = module.convert_notebook({"format": "ipynb", "source": source})["source"]

        self.assert_valid_marimo(converted)
        self.assertIn("日本語", converted)
        self.assertIn("answer = 40 + 2", converted)

    def test_converts_percent_python_without_executing_it(self):
        source = "# %%\nraise RuntimeError('must not execute')\n\n# %%\nanswer = 42\n"

        converted = module.convert_notebook({"format": "python", "source": source})["source"]

        self.assert_valid_marimo(converted)
        self.assertIn("must not execute", converted)
        self.assertIn("answer = 42", converted)

    def test_converts_pip_cell_to_pep_723_without_executing_pip(self):
        source = json.dumps({
            "cells": [
                {"cell_type": "code", "execution_count": None, "metadata": {},
                 "outputs": [], "source": ["!pip install keras\n", "import keras"]},
            ],
            "metadata": {},
            "nbformat": 4,
            "nbformat_minor": 5,
        })

        converted = module.convert_notebook({"format": "ipynb", "source": source})["source"]

        self.assert_valid_marimo(converted)
        self.assertIn('# dependencies = ["keras"]', converted)
        self.assertIn("import keras", converted)
        self.assertNotIn("subprocess.call", converted)

    def test_rejects_unknown_and_oversized_inputs(self):
        with self.assertRaisesRegex(ValueError, "Unsupported import format"):
            module.convert_notebook({"format": "archive", "source": "text"})

        original_limit = module.MAXIMUM_IMPORT_BYTES
        module.MAXIMUM_IMPORT_BYTES = 4
        try:
            with self.assertRaisesRegex(ValueError, "too large"):
                module.convert_notebook({"format": "python", "source": "12345"})
        finally:
            module.MAXIMUM_IMPORT_BYTES = original_limit


if __name__ == "__main__":
    unittest.main()
