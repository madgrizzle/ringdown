#!/usr/bin/env python3
"""Bump the Flutter build number in pubspec.yaml.

  version: 1.0.0+8  ->  version: 1.0.0+9

Usage:
  ./bump_build.sh           # +1
  ./bump_build.sh --patch   # also 1.0.0 -> 1.0.1, and +1
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
PUBSPEC = ROOT / "pubspec.yaml"
VERSION_RE = re.compile(
    r"^(version:\s*)(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$",
    re.MULTILINE,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--patch",
        action="store_true",
        help="also increment the patch version (1.0.0 -> 1.0.1)",
    )
    args = parser.parse_args()

    text = PUBSPEC.read_text(encoding="utf-8")
    match = VERSION_RE.search(text)
    if not match:
        print("Could not find a version: X.Y.Z+N line in pubspec.yaml", file=sys.stderr)
        return 1

    prefix, major, minor, patch, build = match.groups()
    major_i, minor_i, patch_i, build_i = map(int, (major, minor, patch, build))
    old = f"{major_i}.{minor_i}.{patch_i}+{build_i}"

    build_i += 1
    if args.patch:
        patch_i += 1
    new = f"{major_i}.{minor_i}.{patch_i}+{build_i}"

    text, n = VERSION_RE.subn(f"{prefix}{new}", text, count=1)
    if n != 1:
        print("Failed to rewrite pubspec.yaml", file=sys.stderr)
        return 1
    PUBSPEC.write_text(text, encoding="utf-8")
    print(f"{old} -> {new}")
    print("Next: build and publish, then run ./publish_version.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
