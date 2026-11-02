#!/usr/bin/env python3
"""Independent host-side digest audit of disposable simulator archives only."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

simulator_id = sys.argv[1]
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', simulator_id, 'dev.offload.app', 'data'], text=True).strip())
media = Path.home() / 'Library/Developer/CoreSimulator/Devices' / simulator_id / 'data/Media/DCIM'

def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()

source_hashes = {digest(path) for path in media.rglob('*') if path.is_file()}
rows = []
for manifest in sorted((container / 'Documents/TestDrive/Offload').glob('*/receipt.json')):
    receipt = json.loads(manifest.read_text())
    for resource in receipt['resources']:
        assert resource['name'] == 'Offload-Test.jpg', 'Refusing to audit non-test assets'
        archive = manifest.parent / resource['file']
        actual = digest(archive)
        source_exists = resource['sha256'] in source_hashes
        matches = actual == resource['sha256'] and archive.stat().st_size == resource['bytes']
        deliberate_corruption = actual == hashlib.sha256(b'corrupted').hexdigest()
        assert source_exists, 'No matching original source bytes in simulator Photos storage'
        assert matches or deliberate_corruption, 'Unexpected archive mismatch'
        rows.append({'receipt': receipt['id'], 'bytes': resource['bytes'], 'source_sha256_found': source_exists, 'archive_matches_source': matches, 'deliberate_corruption_detected': deliberate_corruption})
assert any(row['archive_matches_source'] for row in rows)
assert any(row['deliberate_corruption_detected'] for row in rows)
print(json.dumps({'environment': 'iOS simulator; generated fixtures only', 'audit': 'PASS', 'resources': rows}, indent=2))
