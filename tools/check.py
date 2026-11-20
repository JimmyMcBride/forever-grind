#!/usr/bin/env python3
"""Run standalone Lua 5.1 and documentation checks from any working directory."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
lua_files = sorted(str(path.relative_to(ROOT)) for path in ROOT.glob("*.lua"))
lua_files += sorted(str(path.relative_to(ROOT)) for path in ROOT.glob("tests/*.lua"))
subprocess.run(["luac5.1", "-p", *lua_files], cwd=ROOT, check=True)
subprocess.run(["lua5.1", "tests/run.lua"], cwd=ROOT, check=True)

for path in [*ROOT.glob("*.lua"), *ROOT.glob("*.toc"), *ROOT.glob("*.md"),
             *ROOT.glob("docs/*.md"), *ROOT.glob("tests/*.lua"), *ROOT.glob("tools/*.py"),
             *ROOT.glob(".github/workflows/*.yml")]:
    content = path.read_text(encoding="utf-8")
    assert content.endswith("\n"), f"Missing final newline: {path.name}"
    assert all(line == line.rstrip() for line in content.splitlines()), f"Trailing whitespace: {path.name}"
    if path.suffix == ".md":
        for link in re.findall(r"\]\(([^)]+)\)", content):
            if "://" not in link and not link.startswith("#"):
                assert (path.parent / link.split("#")[0]).exists(), f"Broken link: {link}"
print("Syntax, behavior, mocked integrations, Markdown links, and whitespace checks passed.")
