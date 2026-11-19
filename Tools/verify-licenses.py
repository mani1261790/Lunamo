#!/usr/bin/env python3
"""Fail packaging on missing, altered or stale license evidence. No network access."""
from pathlib import Path
import hashlib
import json
import re
import sys
from importlib import metadata

root = Path(__file__).resolve().parents[1]
source = root / 'MarimoNative/Resources/Licenses'
app = Path(sys.argv[1]) if len(sys.argv) > 1 else None
actual = app / 'Contents/Resources/Licenses' if app else source
expected = json.loads((source / 'checksums.json').read_text())
for name, digest in expected.items():
    path = actual / name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Missing or altered license: {path}')
inv = json.loads((source / 'inventory.json').read_text())
manifest = json.loads((root / 'MarimoNative/Resources/Sidecar/runtime-manifest.json').read_text())
assert manifest['python']['version'] == inv['python_version'], 'Python license audit is stale'
assert manifest['python']['distribution'].endswith(inv['python_distribution']), 'Python distribution audit is stale'
assert manifest['builder']['uvVersion'] == inv['uv_version'], 'uv license audit is stale'
resolved = json.loads((root / 'Package.resolved').read_text())
for name, version in inv['swift'].items():
    pin = next(p for p in resolved['pins'] if p['identity'].lower() == name.lower())
    assert pin['state']['version'] == version, f'{name} license audit is stale'
if app:
    bundle = app / 'Contents/Resources/Lunamo_MarimoWebFallback.bundle'
    # SwiftPM macOS bundles can be flat or contain Contents/Resources,
    # depending on the toolchain. Bundle.module.resourceURL supports both.
    candidates = [bundle / 'Contents/Resources/Assets', bundle / 'Assets']
    present = [path for path in candidates if path.is_dir()]
    assert len(present) == 1, f'Expected one renderer resource directory, found: {present}'
    renderer = present[0]
else:
    renderer = root / 'MarimoNative/WebFallback/Assets'
for name, digest in inv['renderer_sha256'].items():
    assert hashlib.sha256((renderer / name).read_bytes()).hexdigest() == digest, f'Renderer changed without license review: {name}'
HIGHLIGHT_NOTICES = {'LICENSE': '32036745be91b9d142f5b94fa0d98c90ec67c2efe08dd25fb941c84110addfd6', 'THIRD_PARTY_NOTICES.md': 'e2c6f9da96a42c4565e564dafe9b6033a1f00b70c44f9a81e8cb13a755c5c59e', 'LICENSE-highlight.js': '6c081431591d9df696c82dc598fe1423765b8a299b200ed00b281afd0f64c490'}
reviewed = {name.lower() for name in inv['swift']}
for pin in resolved['pins']:
    if pin['identity'].lower() not in reviewed:
        assert pin['identity'].lower() == 'highlightkit' and pin['state']['version'] == '0.2.0', f'Unreviewed Swift dependency: {pin["identity"]}'
        # This development-only dependency retains both its MIT and highlight.js BSD notices.
        for name, digest in HIGHLIGHT_NOTICES.items():
            path = root / 'MarimoNative/UI/HighlightLicenses' / name
            assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest, f'HighlightKit notice changed: {name}'
assert len(inv['crates']) == 680 and len(inv['web']) == 90, 'Incomplete dependency evidence'
assert all(p.get('sha256') and p.get('license') for p in inv['crates'])
assert all(p.get('integrity') and p.get('license') for p in inv['web'])
# All MPL source URLs must be in the human-readable notice, including dual-license selection.
sources = (actual / 'Source-availability.txt').read_text()
for p in inv['crates']:
    if 'MPL-2.0' in p['license']:
        assert p['url'] in sources, f'Missing MPL source: {p["name"]}'
if app:
    sidecar = app / 'Contents/Resources/Sidecar'
    notice = (sidecar / 'THIRD_PARTY_NOTICES.md').read_text()
    for name in ['## marimo-base 0.24.0', '## marimo-lsp 0.1.0', '## pyzmq 27.1.0', 'Mozilla Public License Version 2.0']:
        assert name in notice, f'Missing sidecar notice: {name}'
    packages = {d.metadata['Name']:d.version for d in metadata.distributions(path=[str(sidecar / 'lib/python3.13/site-packages')])}
    assert packages == inv['python_packages'], 'Python package set changed without license review'
    runtime = json.loads((sidecar / 'runtime-manifest.json').read_text())
    assert runtime == manifest, 'Packaged runtime differs from audited runtime'
print('License evidence verified' + (f': {app}' if app else ''))
