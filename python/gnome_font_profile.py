#!/usr/bin/env python3
"""Gnosis-only GNOME Terminal profile; never change a user's default profile."""
from __future__ import annotations

import ast
import os
import subprocess
import sys
import uuid
from pathlib import Path

LIST_SCHEMA = "org.gnome.Terminal.ProfilesList"
PROFILE_SCHEMA = "org.gnome.Terminal.Legacy.Profile"
NAME = "Gnosis"


def gs(*parts: str) -> str:
    run = subprocess.run(["gsettings", *parts], text=True, capture_output=True, check=True)
    return run.stdout.strip()


def configure(home: Path, family: str, size: int) -> None:
    profile_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"gnosis-terminal:{home.resolve()}"))
    profile_schema = f"{PROFILE_SCHEMA}:/org/gnome/terminal/legacy/profiles:/:{profile_id}/"
    found = gs("get", LIST_SCHEMA, "list")
    try:
        entries = ast.literal_eval(found.removeprefix("@as ").strip())
    except (ValueError, SyntaxError) as exc:
        raise RuntimeError(f"Cannot safely read existing GNOME profiles: {found}") from exc
    if not isinstance(entries, list) or not all(isinstance(x, str) for x in entries):
        raise RuntimeError("GNOME profile list has an unexpected format")
    if profile_id not in entries:
        # Only append; preserve the default and all other terminal profiles.
        gs("set", LIST_SCHEMA, "list", repr(entries + [profile_id]))
    gs("set", profile_schema, "visible-name", NAME)
    gs("set", profile_schema, "use-system-font", "false")
    gs("set", profile_schema, "font", f"{family} {size}")
    verify = gs("get", profile_schema, "font")
    if f"{family} {size}" not in verify:
        raise RuntimeError(f"Could not verify font update: {verify}")
    destination = home / "terminal" / "gnome-profile-id"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(profile_id + "\n", encoding="ascii")


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: gnome_font_profile.py GNOSIS_HOME FAMILY SIZE", file=sys.stderr)
        return 2
    try:
        configure(Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]))
        print(NAME)
    except (OSError, subprocess.CalledProcessError, RuntimeError, ValueError) as exc:
        print(f"Gnosis GNOME font profile: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
