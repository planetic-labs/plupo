#!/usr/bin/env python3
"""Prepend the matching curated changelog section to release installation notes."""
import re
import sys
from pathlib import Path

version, notes_path = sys.argv[1:]
version = version.removeprefix('v')
changelog = Path('CHANGELOG.md').read_text()
match = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
if not match or not match.group(1).strip():
    raise SystemExit(f'Missing CHANGELOG.md entry for {version}')
notes = Path(notes_path)
notes.write_text(f'## Changes in {version}\n\n{match.group(1).strip()}\n\n' + notes.read_text())
