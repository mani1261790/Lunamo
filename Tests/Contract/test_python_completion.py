"""Contract for static Python completion in the bundled sidecar."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "native_launcher", root / "MarimoNative/Resources/Sidecar/launch_marimo_lsp.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PythonCompletionTests(unittest.TestCase):
    def test_member_completion_returns_bounded_structured_items(self):
        result = module.complete_python({
            "source": "import os\nos.pa", "line": 1, "column": 5
        })
        self.assertIn("path", [item["label"] for item in result["items"]])
        self.assertLessEqual(len(result["items"]), 80)
        self.assertTrue(all("label" in item and "kind" in item
                            for item in result["items"]))

    def test_completion_never_executes_notebook_source(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "executed"
            source = f'open({str(marker)!r}, "w").write("bad")\nstr.up'
            result = module.complete_python({
                "source": source, "line": 1, "column": 6
            })
            self.assertFalse(marker.exists())
            self.assertIn("upper", [item["label"] for item in result["items"]])

    def test_invalid_and_oversized_requests_are_empty(self):
        self.assertEqual(module.complete_python({
            "source": "x", "line": -1, "column": 0
        }), {"items": []})
        self.assertEqual(module.complete_python({
            "source": "x" * (module.MAXIMUM_COMPLETION_BYTES + 1),
            "line": 0,
            "column": 0,
        }), {"items": []})


if __name__ == "__main__":
    unittest.main()
