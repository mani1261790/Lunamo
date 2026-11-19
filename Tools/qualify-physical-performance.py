#!/usr/bin/env python3
"""Measure the app extracted from the final DMG on a physical Apple Silicon Mac."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--checklist', type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Choose a new output path; existing evidence is not overwritten")
    artifact = args.artifact.resolve()
    model = subprocess.check_output(['sysctl', '-n', 'hw.model'], text=True).strip()
    virtual = subprocess.check_output(
        ['sysctl', '-n', 'kern.hv_vmm_present'], text=True).strip() != '0'
    if virtual or not model.startswith('Mac') or platform.machine() != 'arm64':
        raise SystemExit('Run qualification on a physical Apple Silicon Mac')
    with artifact.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    checklist = None
    if args.checklist:
        import yaml
        checklist = yaml.safe_load(args.checklist.read_text())
        if checklist.get('artifactSHA256') != digest:
            raise SystemExit('Checklist does not match the supplied DMG')
    subprocess.run(['xcrun', 'stapler', 'validate', str(artifact)], check=True)
    info = plistlib.loads(subprocess.check_output(
        ['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(artifact)]))
    mount = next(Path(item['mount-point']) for item in info['system-entities'] if 'mount-point' in item)
    try:
        with tempfile.TemporaryDirectory(prefix='lunamo-physical-qualification-') as directory:
            app = Path(directory) / 'Lunamo.app'
            try:
                subprocess.run(['ditto', str(mount / 'Lunamo.app'), str(app)], check=True)
                subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
                result = subprocess.run(
                    [str(Path(__file__).with_name('measure-release-performance.py')), str(app)],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                print(result.stdout, end='')
                log = args.output.with_suffix('.log')
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text(result.stdout)
                if result.returncode:
                    raise SystemExit('Performance failed; no passing report or checklist update was written')
                patterns = {
                    'launchP95Milliseconds': r'cold-window p95=([0-9.]+)',
                    'launchSamples': r'cold-window p95=[0-9.]+ms samples=([0-9]+)',
                    'residentMiB': r'app-sidecar-rss=([0-9.]+)',
                    'scrollMaxMilliseconds': r'main-thread-max-delay=([0-9.]+)',
                }
                metrics = {key: float(re.search(pattern, result.stdout).group(1))
                           for key, pattern in patterns.items()}
                report = {'schemaVersion': 1, 'artifactSHA256': digest,
                          'performedAt': datetime.now(timezone.utc).isoformat(),
                          'host': {'architecture': platform.machine(), 'model': model,
                                   'macOS': platform.mac_ver()[0], 'virtualMachine': virtual},
                          'metrics': metrics}
                args.output.write_text(json.dumps(report, indent=2) + '\n')
                if checklist is not None:
                    checklist = yaml.safe_load(args.checklist.read_text())
                    if checklist.get('artifactSHA256') != digest:
                        raise SystemExit('Checklist artifact changed during measurement')
                    checklist['physicalPerformanceReport'] = os.path.relpath(
                        args.output.resolve(), args.checklist.resolve().parent)
                    args.checklist.write_text(yaml.safe_dump(checklist, sort_keys=False))
                print(f'Physical performance report: {args.output}')
            finally:
                # The signed sidecar has deliberately read-only directories.
                for path in app.rglob('*'):
                    if path.is_dir() and not path.is_symlink():
                        path.chmod(path.stat().st_mode | 0o200)
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True)


if __name__ == '__main__':
    main()
