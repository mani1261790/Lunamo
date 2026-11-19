import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_requirements', ROOT / 'Tools/verify-requirements.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class PhysicalPerformanceGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.artifact = self.root / 'candidate.dmg'
        self.artifact.write_bytes(b'test artifact')
        self.digest = hashlib.sha256(self.artifact.read_bytes()).hexdigest()
        self.report = {'schemaVersion': 1, 'artifactSHA256': self.digest,
                       'performedAt': '2026-11-19T13:00:00+00:00',
                       'host': {'architecture': 'arm64', 'model': 'Mac14,3', 'virtualMachine': False},
                       'metrics': {'launchP95Milliseconds': 500, 'launchSamples': 20,
                                   'residentMiB': 210, 'scrollMaxMilliseconds': 70}}
        self.report_path = self.root / 'performance.json'

    def verify(self, report):
        self.report_path.write_text(json.dumps(report))
        gate.verify_physical_performance(self.report_path, self.digest)

    def test_accepts_bound_physical_measurement(self):
        self.verify(self.report)

    def test_rejects_wrong_artifact(self):
        self.report['artifactSHA256'] = 'another artifact'
        with self.assertRaises(SystemExit): self.verify(self.report)

    def test_rejects_virtual_host(self):
        self.report['host']['virtualMachine'] = True
        with self.assertRaises(SystemExit): self.verify(self.report)

    def test_rejects_invalid_measurements(self):
        for field, value in [('scrollMaxMilliseconds', 100.01), ('residentMiB', 351),
                             ('launchP95Milliseconds', 2001), ('scrollMaxMilliseconds', float('nan')),
                             ('scrollMaxMilliseconds', None), ('launchSamples', 19), ('launchSamples', float('nan')), ('launchSamples', True)]:
            with self.subTest(field=field, value=value):
                report = copy.deepcopy(self.report)
                report['metrics'][field] = value
                with self.assertRaises(SystemExit): self.verify(report)

    def test_checklist_cannot_omit_physical_report(self):
        checklist = {'schemaVersion': 1, 'artifactSHA256': self.digest, 'executor': 'Test',
                     'performedAt': self.report['performedAt'], 'requirements': {}}
        path = self.root / 'checklist.yml'
        path.write_text(yaml.safe_dump(checklist))
        with self.assertRaises(SystemExit): gate.verify_release_checklist(path, self.artifact, set())
        self.verify(self.report)
        checklist['physicalPerformanceReport'] = self.report_path.name
        path.write_text(yaml.safe_dump(checklist))
        gate.verify_release_checklist(path, self.artifact, set())


if __name__ == '__main__':
    unittest.main()
