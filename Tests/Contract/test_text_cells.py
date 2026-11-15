"""Contract for the native command added to the pinned marimo-lsp server."""
import ast
import importlib.util
from pathlib import Path
import unittest

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "native_launcher", root / "MarimoNative/Resources/Sidecar/launch_marimo_lsp.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TextCellTests(unittest.TestCase):
    def test_new_round_trip(self):
        for text in ["", "# 日本語\n\n**強調**", '"""', "'''", "\\", "{value}",
                     "line\n    indent\n", "x\x00y", "🙂 café"]:
            with self.subTest(text=text):
                created = module.text_cell({"markdown": text})
                ast.parse(created["source"])
                self.assertNotIn("import marimo as _mo", created["source"])
                self.assertTrue(created["source"].startswith('__import__("marimo").md('))
                parsed = module.text_cell({"source": created["source"]})
                self.assertEqual(parsed["markdown"], text)
                self.assertEqual(module.text_cell({
                    "source": created["source"], "markdown": text
                })["source"], created["source"])

    def test_preserves_unchanged_source(self):
        for source in ['mo.md(r"""# Hello\nworld""")', "mo.md('hello') # comment",
                       'import marimo as _mo\n_mo.md("日本語")',
                       '__import__("marimo").md("binding free")']:
            parsed = module.text_cell({"source": source})
            self.assertIsNotNone(parsed["markdown"])
            self.assertEqual(module.text_cell({
                "source": source, "markdown": parsed["markdown"]})["source"], source)

    def test_edits_preserve_surrounding_source(self):
        source = '# 日本語\nmo.md("old") # retained\n'
        updated = module.text_cell({"source": source, "markdown": 'new "quotes" \\'})
        self.assertTrue(updated["source"].startswith('# 日本語\nmo.md('))
        self.assertTrue(updated["source"].endswith(') # retained\n'))
        self.assertEqual(module.text_cell({"source": updated["source"]})["markdown"],
                         'new "quotes" \\')

    def test_dynamic_and_mixed_cells_stay_python(self):
        for source in ['mo.md(f"{value}")', 'mo.md(content)', 'x = 1\nmo.md("text")',
                       'mo.md("text", width=100)', '__import__("os").system("echo nope")']:
            result = module.text_cell({"source": source})
            self.assertIsNone(result["markdown"])
            self.assertEqual(result["source"], source)


if __name__ == "__main__":
    unittest.main()
