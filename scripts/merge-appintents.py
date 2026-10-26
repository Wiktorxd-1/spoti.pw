#!/usr/bin/env python3
"""Adds a Metadata.appintents to the app's own inside an IPA, in place.

  scripts/merge-appintents.py <ipa> <Payload/X.app/> <Metadata.appintents dir>

The system looks an intent up in the metadata of the bundle that runs it, and a LiveActivityIntent
runs in the app, so the mod's intents and shortcuts have to be listed in Spotify's file next to its own.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

def merge_list(theirs, added, identity=None):
    merged = list(theirs or [])
    positions = ({item.get(identity): i for i, item in enumerate(merged)
                  if isinstance(item, dict) and item.get(identity) is not None} if identity else {})
    for item in added or []:
        key = item.get(identity) if identity and isinstance(item, dict) else None
        if key is not None and key in positions:
            merged[positions[key]] = item
        elif item not in merged:
            if key is not None:
                positions[key] = len(merged)
            merged.append(item)
    return merged


def merge_section(name, theirs, added, identity=None):
    if theirs is None:
        return added
    if added is None or not added:
        return theirs
    if not theirs:
        return added
    if isinstance(theirs, dict) and isinstance(added, dict):
        return {**theirs, **added}
    if isinstance(theirs, list) and isinstance(added, list):
        return merge_list(theirs, added, identity)
    raise TypeError(f"App Intents section {name!r} changed shape from "
                    f"{type(theirs).__name__} to {type(added).__name__}")


def merge_metadata(theirs, added):
    if theirs is None:
        return added
    merged = dict(theirs)
    sections = {
        "actions": None,
        "assistantEntities": "identifier",
        "assistantIntents": "identifier",
        "entities": None,
        "queries": None,
        "enums": "identifier",
        "autoShortcuts": "actionIdentifier",
    }
    for section, identity in sections.items():
        if section in added:
            merged[section] = merge_section(section, theirs.get(section), added[section], identity)
    # A bundle records one provider. Keep Spotify's when it has one; the merged static shortcut
    # descriptions still expose Taurus's shortcuts without replacing Spotify's provider.
    if "autoShortcutProviderMangledName" not in merged and "autoShortcutProviderMangledName" in added:
        merged["autoShortcutProviderMangledName"] = added["autoShortcutProviderMangledName"]
    return merged


def main():
    ipa, app_dir, ours = sys.argv[1:4]
    member = f"{app_dir}Metadata.appintents/extract.actionsdata"
    version = f"{app_dir}Metadata.appintents/version.json"

    with zipfile.ZipFile(ipa) as z:
        theirs = json.loads(z.read(member)) if member in z.namelist() else None
    with open(os.path.join(ours, "extract.actionsdata")) as f:
        added = json.load(f)

    merged = merge_metadata(theirs, added)
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, os.path.dirname(member)))
        with open(os.path.join(tmp, member), "w") as f:
            json.dump(merged, f)
        entries = [member]
        if theirs is None:
            shutil.copy(os.path.join(ours, "version.json"), os.path.join(tmp, version))
            entries.append(version)
        subprocess.run(["zip", "-q", os.path.abspath(ipa), *entries], cwd=tmp, check=True)

    print(f"    {len(added['actions'])} actions and {len(added.get('autoShortcuts', []))} shortcuts added "
          f"to {len(merged['actions']) - len(added['actions'])} actions and "
          f"{len(merged.get('autoShortcuts', [])) - len(added.get('autoShortcuts', []))} shortcuts of the app's")


if __name__ == "__main__":
    main()
