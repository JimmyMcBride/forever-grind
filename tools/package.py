#!/usr/bin/env python3
"""Build and verify a deterministic install ZIP without development files."""
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
toc = ROOT / "ForeverGrind.toc"
content = toc.read_text(encoding="utf-8")
version = re.search(r"^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$", content, re.MULTILINE).group(1)
runtime = [line.strip() for line in content.splitlines() if line.strip() and not line.startswith("#")]
assert runtime == ["Util.lua", "Session.lua", "Valuation.lua", "Parsing.lua", "Collector.lua",
                   "XPBar.lua", "UI.lua", "Core.lua"], "Unexpected TOC load order"
files = [toc.name, *runtime, "README.md", "docs/IN_GAME_TESTING.md"]
output = ROOT / "dist" / f"ForeverGrind-{version}.zip"
output.parent.mkdir(exist_ok=True)
with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
    for name in files:
        entry = ZipInfo("ForeverGrind/" + name, date_time=(1980, 1, 1, 0, 0, 0))
        entry.compress_type = ZIP_DEFLATED
        entry.external_attr = 0o100644 << 16
        archive.writestr(entry, (ROOT / name).read_bytes())
with ZipFile(output) as archive:
    assert archive.testzip() is None, "Corrupt ZIP entry"
    assert set(archive.namelist()) == {"ForeverGrind/" + name for name in files}
    for name in files:
        assert archive.read("ForeverGrind/" + name) == (ROOT / name).read_bytes()
print(output)
print(f"Verified {len(files)} files under one ForeverGrind/ directory.")
