"""Ensure release coverage cannot silently skip suffixed requirement IDs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("coverage_verifier", ROOT / "Tools/verify-requirements.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class RequirementCoverageTests(unittest.TestCase):
    def test_mandatory_suffixed_requirements_are_included(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "MarimoNative_Strict_Specification_v1.0.md").write_text(
                "MN-ENV-019 MUST\nMN-ENV-019A MUST\nMN-ENV-019B MUST NOT\n"
                "MN-ENV-020 SHOULD\nMN-ENV-021 MAY\n"
            )
            self.assertEqual(verifier.specification_requirements(root),
                             {"MN-ENV-019", "MN-ENV-019A", "MN-ENV-019B"})


if __name__ == "__main__":
    unittest.main()
