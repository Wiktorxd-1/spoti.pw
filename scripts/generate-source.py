#!/usr/bin/env python3
import os
import sys
import glob
import json
import re
import subprocess
import zipfile
import plistlib
from datetime import datetime, timezone

def get_app_version(root_dir):
    version_file = os.path.join(root_dir, 'version.txt')
    if os.path.isfile(version_file):
        with open(version_file, 'r', encoding='utf-8') as f:
            v = f.read().strip()
            if v:
                return v
    return '0.60.5'

def get_commit_number(root_dir):
    try:
        out = subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], cwd=root_dir).decode().strip()
        if out.isdigit():
            return out
    except Exception:
        pass
    return os.environ.get('GITHUB_RUN_NUMBER', '1')

def get_repo(root_dir):
    repo = os.environ.get('GITHUB_REPOSITORY')
    if repo:
        return repo
    for remote in ['origin', 'fork']:
        try:
            url = subprocess.check_output(['git', 'remote', 'get-url', remote], cwd=root_dir).decode().strip()
            if url.endswith('.git'):
                url = url[:-4]
            m = re.search(r'github\.com[:/]([^/]+/[^/]+)', url)
            if m:
                return m.group(1)
        except Exception:
            pass
    return 'Wiktorxd-1/spoti.pw'

def get_spotify_version_from_ipa(ipa_path):
    if not ipa_path or not os.path.isfile(ipa_path):
        return '9.1.94'
    try:
        with zipfile.ZipFile(ipa_path, 'r') as z:
            for name in z.namelist():
                if name.endswith('Spotify.app/Info.plist'):
                    plist = plistlib.loads(z.read(name))
                    return plist.get('CFBundleShortVersionString', '9.1.94')
    except Exception:
        pass
    return '9.1.94'

def main():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    ipa_path = sys.argv[1] if len(sys.argv) > 1 else None

    if not ipa_path:
        ipas = glob.glob(os.path.join(root_dir, 'out', 'Taurus*.ipa')) + \
               glob.glob(os.path.join(root_dir, 'out', '*.ipa')) + \
               glob.glob(os.path.join(root_dir, 'ipa', '*.ipa'))
        if ipas:
            ipa_path = ipas[0]

    ipa_size = os.path.getsize(ipa_path) if ipa_path and os.path.isfile(ipa_path) else 132877139
    ipa_name = os.path.basename(ipa_path) if ipa_path else 'Taurus.ipa'

    app_version = get_app_version(root_dir)
    commit_num = get_commit_number(root_dir)
    full_version = f"{app_version}-{commit_num}-Alpha"

    now_utc = datetime.now(timezone.utc)
    date_str = now_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    date_short = now_utc.strftime("%Y-%m-%d")

    repo = get_repo(root_dir)
    spotify_version = get_spotify_version_from_ipa(ipa_path)
    tag = f"v{spotify_version}"

    download_url = os.environ.get('IPA_DOWNLOAD_URL')
    if not download_url:
        download_url = f"https://github.com/{repo}/releases/download/{tag}/{ipa_name}"

    source_data = {
        "name": "taurus",
        "identifier": "pw.taurus.source",
        "subtitle": "Taurus releases for SideStore and Feather",
        "iconURL": "https://thumb.wikimedia.org/wikipedia/commons/thumb/7/74/Spotify_App_Logo.svg/960px-Spotify_App_Logo.svg.png",
        "website": "https://github.com/samj-exe/taurus",
        "tintColor": "0A4B00",
        "apps": [
            {
                "name": "taurus",
                "bundleIdentifier": "com.spotify.client",
                "developerName": "samj.",
                "subtitle": "taurus: the free, open-sourced alternative to chroma.pw with built-in spotify premium",
                "localizedDescription": "Open-Sourced fork of chroma.pw with built-in Spotify Premium. The Redesigned UI requires iOS 26; the legacy UI supports iOS 16.1 and later.",
                "iconURL": "https://thumb.wikimedia.org/wikipedia/commons/thumb/7/74/Spotify_App_Logo.svg/960px-Spotify_App_Logo.svg.png",
                "tintColor": "0A4B00",
                "version": full_version,
                "versionDate": date_short,
                "downloadURL": download_url,
                "size": ipa_size,
                "versions": [
                    {
                        "version": full_version,
                        "date": date_str,
                        "downloadURL": download_url,
                        "size": ipa_size,
                        "minOSVersion": "16.1"
                    }
                ],
                "appPermissions": {}
            }
        ]
    }

    apps_json_path = os.path.join(root_dir, 'apps.json')
    sidestore_json_path = os.path.join(root_dir, 'sidestore.json')

    with open(apps_json_path, 'w', encoding='utf-8') as f:
        json.dump(source_data, f, indent=2)
        f.write('\n')

    with open(sidestore_json_path, 'w', encoding='utf-8') as f:
        json.dump(source_data, f, indent=2)
        f.write('\n')

    print(f"==> generated {apps_json_path} and {sidestore_json_path}")
    print(f"    version: {full_version}")
    print(f"    date:    {date_str}")
    print(f"    url:     {download_url}")
    print(f"    size:    {ipa_size} bytes")

if __name__ == '__main__':
    main()
