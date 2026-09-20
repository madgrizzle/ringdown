#!/usr/bin/env python3
"""Tell the gateway that a new Ringdown build is live on Play Store / TestFlight.

Reads version from pubspec.yaml and updates /opt/nms-alert-gateway/app_version.json
on mail.phionalerter.com. The API picks this up on the next /app/version request
(no restart).

Run this AFTER the new build is available to users.

Usage:
  ./publish_version.sh
  ./publish_version.sh --android-only
  ./publish_version.sh --ios-only
  ./publish_version.sh --ios-url https://testflight.apple.com/join/XXXX
  ./publish_version.sh --min-build 8
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent
PUBSPEC = ROOT / "pubspec.yaml"
LOCAL_COPY = pathlib.Path("/home/john/phionalerter-server/app_version.json")
VERSION_RE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.MULTILINE)

SSH_USER = os.environ.get("RINGDOWN_SSH_USER", "john")
SSH_HOST = os.environ.get("RINGDOWN_SSH_HOST", "mail.phionalerter.com")
SSH_KEY = os.path.expanduser(os.environ.get("RINGDOWN_SSH_KEY", "~/.ssh/alerter"))
REMOTE_FILE = os.environ.get(
    "RINGDOWN_APP_VERSION_FILE",
    "/opt/nms-alert-gateway/app_version.json",
)


def read_pubspec() -> tuple[str, int]:
    text = PUBSPEC.read_text(encoding="utf-8")
    match = VERSION_RE.search(text)
    if not match:
        raise SystemExit("Could not find version: X.Y.Z+N in pubspec.yaml")
    return match.group(1), int(match.group(2))


def ssh(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    cmd = [
        "ssh",
        "-i",
        SSH_KEY,
        "-o",
        "IdentitiesOnly=yes",
        f"{SSH_USER}@{SSH_HOST}",
        *args,
    ]
    return subprocess.run(cmd, check=True, **kwargs)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-only", action="store_true")
    parser.add_argument("--ios-only", action="store_true")
    parser.add_argument(
        "--ios-url",
        help="TestFlight join URL to store in ios.store_url",
    )
    parser.add_argument(
        "--min-build",
        type=int,
        help="apps older than this cannot dismiss the update prompt",
    )
    args = parser.parse_args()
    if args.android_only and args.ios_only:
        print("Use only one of --android-only / --ios-only", file=sys.stderr)
        return 1

    version, build = read_pubspec()
    platforms = ["android", "ios"]
    if args.android_only:
        platforms = ["android"]
    elif args.ios_only:
        platforms = ["ios"]

    raw = ssh(["sudo", "cat", REMOTE_FILE], capture_output=True, text=True).stdout
    data = json.loads(raw)

    for name in platforms:
        entry = data.setdefault(name, {})
        entry["version"] = version
        entry["build"] = build
        if args.min_build is not None:
            entry["min_build"] = args.min_build
        if name == "ios" and args.ios_url:
            entry["store_url"] = args.ios_url
        data[name] = entry

    payload = json.dumps(data, indent=2) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as tmp:
        tmp.write(payload)
        tmp_path = tmp.name
    try:
        subprocess.run(
            [
                "scp",
                "-i",
                SSH_KEY,
                "-o",
                "IdentitiesOnly=yes",
                tmp_path,
                f"{SSH_USER}@{SSH_HOST}:/tmp/app_version.json",
            ],
            check=True,
        )
    finally:
        os.unlink(tmp_path)

    ssh(
        [
            f"sudo cp /tmp/app_version.json {REMOTE_FILE} && "
            f"sudo chown nmsadmin:nmsadmin {REMOTE_FILE}",
        ]
    )

    if LOCAL_COPY.parent.is_dir():
        LOCAL_COPY.write_text(payload, encoding="utf-8")

    print(f"Published {version}+{build} for {', '.join(platforms)}")
    print(f"  {SSH_USER}@{SSH_HOST}:{REMOTE_FILE}")
    for name in platforms:
        print(f"  {name}: version={data[name].get('version')} build={data[name].get('build')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
