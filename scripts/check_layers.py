import os, re, sys

sources = os.path.join("tweak", "Sources")
rules = [
    ("Core", r"Settings|Shared|Native|Redesigned|App"),
    ("Headers", r"Core|Settings|Shared|Native|Redesigned|App"),
    ("Diagnostics", r"Settings|Shared|Native|Redesigned|App"),
    ("Settings", r"Shared|Native|Redesigned|App"),
    ("Shared", r"Native|Redesigned|App"),
    ("Native", r"Redesigned|App"),
    ("Redesigned", r"Native|App"),
]

status = 0
for layer, pattern in rules:
    layer_dir = os.path.join(sources, layer)
    if not os.path.isdir(layer_dir):
        continue
    regex = re.compile(r'#import\s+["<](' + pattern + r")/")
    for root, dirs, files in os.walk(layer_dir):
        for f in files:
            if f.endswith((".m", ".x", ".h")):
                p = os.path.join(root, f)
                with open(p, "r", encoding="utf-8", errors="ignore") as fp:
                    for idx, line in enumerate(fp, 1):
                        if regex.search(line):
                            print(f"Layer violation in {p}:{idx}: {line.strip()}")
                            status = 1

if status == 0:
    print("SUCCESS: All layer boundaries respected perfectly!")
sys.exit(status)
