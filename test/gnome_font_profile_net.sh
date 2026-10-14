#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/gnosis-home"
cat > "$WORK/bin/gsettings" <<'PY'
#!/usr/bin/env python3
import ast
import json
import os
import sys
from pathlib import Path

path = Path(os.environ["MOCK_GSETTINGS_STATE"])
state = json.loads(path.read_text()) if path.exists() else {
    "profiles": ["original-profile"],
    "settings": {"original-profile": {"font": "Monospace 11"}},
}
verb, schema, key, *args = sys.argv[1:]
if schema == "org.gnome.Terminal.ProfilesList" and key == "list":
    if verb == "get":
        print(repr(state["profiles"]))
    elif verb == "set":
        state["profiles"] = ast.literal_eval(args[0])
    else:
        raise SystemExit(3)
elif schema.startswith("org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:"):
    name = schema.split(":")[-2].strip("/")
    if verb == "set":
        state["settings"].setdefault(name, {})[key] = args[0]
    elif verb == "get":
        print(repr(state["settings"].get(name, {}).get(key, "")))
    else:
        raise SystemExit(4)
else:
    raise SystemExit(5)
path.write_text(json.dumps(state))
PY
chmod +x "$WORK/bin/gsettings"
export MOCK_GSETTINGS_STATE="$WORK/state.json"
PATH="$WORK/bin:$PATH" python3 "$REPO/python/gnome_font_profile.py" "$WORK/gnosis-home" "DejaVu Sans Mono" 17 >"$WORK/out1.txt"
PATH="$WORK/bin:$PATH" python3 "$REPO/python/gnome_font_profile.py" "$WORK/gnosis-home" "DejaVu Sans Mono" 21 >"$WORK/out2.txt"
python3 - "$WORK" <<'PY'
import json, sys
from pathlib import Path
work = Path(sys.argv[1])
state = json.loads((work / "state.json").read_text())
profile_id = (work / "gnosis-home" / "terminal" / "gnome-profile-id").read_text().strip()
assert len(state["profiles"]) == 2, state
assert state["profiles"][0] == "original-profile", state
assert profile_id in state["profiles"], state
assert state["settings"]["original-profile"]["font"] == "Monospace 11", state
assert state["settings"][profile_id]["font"] == "DejaVu Sans Mono 21", state
assert state["settings"][profile_id]["visible-name"] == "Gnosis", state
assert state["settings"][profile_id]["use-system-font"] == "false", state
print("OK GNOME dedicated profile, font update, original profile preserved")
PY
