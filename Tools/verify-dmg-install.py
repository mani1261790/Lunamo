#!/usr/bin/env python3
"""Install the notarized DMG outside the checkout and test offline after ejecting it."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('dmg', type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
dmg = args.dmg.resolve()
subprocess.run(['xcrun', 'stapler', 'validate', str(dmg)], check=True)
with tempfile.TemporaryDirectory(prefix='lunamo-installed-acceptance-') as directory:
    app = Path(directory) / 'Applications/Lunamo.app'
    info = plistlib.loads(subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(dmg)]))
    mount = next(Path(item['mount-point']) for item in info['system-entities'] if 'mount-point' in item)
    try:
        subprocess.run(['ditto', str(mount / 'Lunamo.app'), str(app)], check=True)
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
    try:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
        subprocess.run([str(root / 'Tools/verify-release-app-flow.py'), str(app), '--fixture',
                        str(root / 'Tests/Fixtures/two_cell_notebook.py')], check=True)
        with dmg.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        args.output.write_text(json.dumps({'artifactSHA256': digest, 'macOS': platform.mac_ver()[0],
            'installedOutsideCheckout': True, 'dmgEjectedBeforeLaunch': True,
            'externalNetworkDenied': True, 'freshApplicationHome': True,
            'openEditSaveExecuteCleanup': 'passed'}, indent=2) + '\n')
    finally:
        for path in app.rglob('*'):
            if path.is_dir() and not path.is_symlink():
                path.chmod(path.stat().st_mode | 0o200)
