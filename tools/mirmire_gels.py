#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Adds the colour (gel) of each console Mirmire Cartouche added to app/studio/studio_tokens.gd, beside Cartouche's own
gels, and updates the file's hash, as its test expects. Run again after adding a console: a gel already there is left as
it is.

Usage: tools/mirmire_gels.py
"""
import hashlib
import pathlib
import re

TOKENS = pathlib.Path(__file__).resolve().parent.parent / "app/studio/studio_tokens.gd"

# By console folder: the colour its maker is known by, picked to sit with Cartouche's gels.
GELS = {
    "3ds_xl": "#c8262f",
    "atari2600": "#b8692a",
    "atarilynx": "#ec7a1c",
    "ngp": "#3a57a6",
    "ngpc": "#d39a17",
    "ps3": "#3b5ea8",
    "saturn": "#4a5a8c",
    "steam_deck": "#1a8fe0",
    "steam_deck_streaming": "#4fb3e8",
    "wiiu": "#0b9cc4",
}


def main() -> None:
    text = TOKENS.read_text()
    match = re.search(r"^const GEL: Dictionary\[StringName, Color\] = \{(.*)\}$", text, re.M)
    if not match:
        raise SystemExit("no GEL table in studio_tokens.gd")
    entries = match.group(1)
    added = [f'&"{folder}": Color("{colour}")' for folder, colour in GELS.items() if f'&"{folder}":' not in entries]
    if added:
        entries = entries + ", " + ", ".join(added)
        text = text[: match.start(1)] + entries + text[match.end(1):]
    lines = text.split("\n")
    kept = [line for line in lines if not line.startswith("const SHA256 := ")]
    digest = hashlib.sha256("\n".join(kept).encode()).hexdigest()
    lines = [f'const SHA256 := "{digest}"' if line.startswith("const SHA256 := ") else line for line in lines]
    TOKENS.write_text("\n".join(lines))
    print(f"{len(added)} gels added" if added else "every gel is there already")


if __name__ == "__main__":
    main()
