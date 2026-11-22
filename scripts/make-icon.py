#!/usr/bin/env python3
"""Package generated artwork into a modern PNG-backed ICNS (no image redrawing)."""
from pathlib import Path
import struct
import subprocess

root = Path(__file__).resolve().parent.parent
source = root / 'branding/app-icon-dark.png'
light = root / 'branding/app-icon-light.png'
iconset = root / '.build/AppIcon.iconset'
iconset.mkdir(parents=True, exist_ok=True)
entries = []
for tag, size in [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128),
                  ('ic08', 256), ('ic09', 512), ('ic10', 1024)]:
    target = iconset / f'{size}.png'
    subprocess.run(['sips', '-z', str(size), str(size), str(source), '--out', str(target)],
                   check=True, stdout=subprocess.DEVNULL)
    data = target.read_bytes()
    entries.append(tag.encode() + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(entries)
(root / 'Focuselle/Resources/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
subprocess.run(['sips', '-z', '256', '256', str(source), '--out', str(root / 'landing/dist/assets/app-icon.png')],
               check=True, stdout=subprocess.DEVNULL)
subprocess.run(['sips', '-z', '512', '512', str(light), '--out', str(root / 'Focuselle/Resources/AppIconLight.png')],
               check=True, stdout=subprocess.DEVNULL)
print('Built: dark ICNS, light PNG and landing icon')
