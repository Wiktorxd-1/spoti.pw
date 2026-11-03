#!/usr/bin/env python3
"""
scripts/check-syntax.py

Fast pre-flight syntax and logic linter for spoti.pw.
Runs in < 1 second on any machine (macOS, Linux, Windows) before full IPA builds.
Validates:
  1. Python syntax across all project scripts
  2. JSON validity (apps.json, sidestore.json, etc.)
  3. Architecture layer boundaries (Core <- Settings <- Shared <- Native | Redesigned <- App)
  4. Logos directives (%hook, %group, %subclass matching %end)
  5. Preprocessor balance (#if/#ifdef/#ifndef matching #endif)
  6. Static function ordering (ensures static functions called before definition have prototypes)
"""

import os
import re
import sys
import json
import py_compile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCES = os.path.join(ROOT, "tweak", "Sources")

errors = []


def log_error(msg):
    errors.append(msg)
    print(f"::error::{msg}")


def strip_comments_and_strings(code):
    def repl(m):
        if m.group(1):
            return " "
        return '""'

    pattern = r'(/\*.*?\*/|//[^\r\n]*)|("(?:\\.|[^"\\])*")'
    return re.sub(pattern, repl, code, flags=re.DOTALL)


# 1. Python Syntax Check
print("==> [1/6] Checking Python syntax...")
for root, dirs, files in os.walk(ROOT):
    if any(p in root for p in [".git", "theos", ".theos", "build", "node_modules", "scratch"]):
        continue
    for f in files:
        if f.endswith(".py"):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, ROOT)
            try:
                py_compile.compile(p, doraise=True)
            except py_compile.PyCompileError as e:
                log_error(f"Python syntax error in {rel}: {e}")

# 2. JSON Files Check
print("==> [2/6] Validating JSON files...")
for f in ["apps.json", "sidestore.json"]:
    p = os.path.join(ROOT, f)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as fp:
                json.load(fp)
        except Exception as e:
            log_error(f"Malformed JSON in {f}: {e}")

# 3. Layer Boundary Check
print("==> [3/6] Checking architecture layer boundaries...")
layer_rules = [
    ("Core", r"Settings|Shared|Native|Redesigned|App"),
    ("Headers", r"Core|Settings|Shared|Native|Redesigned|App"),
    ("Diagnostics", r"Settings|Shared|Native|Redesigned|App"),
    ("Settings", r"Shared|Native|Redesigned|App"),
    ("Shared", r"Native|Redesigned|App"),
    ("Native", r"Redesigned|App"),
    ("Redesigned", r"Native|App"),
]
for layer, pattern in layer_rules:
    layer_dir = os.path.join(SOURCES, layer)
    if not os.path.isdir(layer_dir):
        continue
    regex = re.compile(rf'#import\s+"({pattern})/')
    for root, _, files in os.walk(layer_dir):
        for f in files:
            if f.endswith((".x", ".m", ".h")):
                p = os.path.join(root, f)
                rel = os.path.relpath(p, ROOT)
                with open(p, "r", encoding="utf-8", errors="ignore") as fp:
                    for i, line in enumerate(fp, 1):
                        if regex.search(line):
                            log_error(f"Layer boundary violation at {rel}:{i}: {line.strip()}")

# 4. Logos Directive Check (%hook, %group, %subclass vs %end)
print("==> [4/6] Verifying Logos blocks balance...")
for root, _, files in os.walk(SOURCES):
    for f in files:
        if f.endswith(".x"):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, ROOT)
            with open(p, "r", encoding="utf-8", errors="ignore") as fp:
                raw = fp.read()
            cleaned = strip_comments_and_strings(raw)
            opens = len(re.findall(r"^\s*%(hook|group|subclass)\b", cleaned, re.M))
            closes = len(re.findall(r"^\s*%end\b", cleaned, re.M))
            if opens != closes:
                log_error(f"Logos block mismatch in {rel}: {opens} opening directives vs {closes} %end")

# 5. Preprocessor Balance Check (#if / #ifdef / #ifndef vs #endif)
print("==> [5/6] Checking preprocessor #if / #endif balance...")
for root, _, files in os.walk(SOURCES):
    for f in files:
        if f.endswith((".x", ".m", ".h")):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, ROOT)
            with open(p, "r", encoding="utf-8", errors="ignore") as fp:
                raw = fp.read()
            cleaned = strip_comments_and_strings(raw)
            ifs = len(re.findall(r"^\s*#\s*(if|ifdef|ifndef)\b", cleaned, re.M))
            endifs = len(re.findall(r"^\s*#\s*endif\b", cleaned, re.M))
            if ifs != endifs:
                log_error(f"Preprocessor mismatch in {rel}: {ifs} #if vs {endifs} #endif")

# 6. Static Function Declaration Ordering Check
print("==> [6/6] Checking static function declarations and prototypes...")
func_def_re = re.compile(
    r"^\s*static\s+([A-Za-z0-9_]+(?:\s*\*+)?)\s+([A-Za-z0-9_]+)\s*\([^;)]*\)[^;{]*\{",
    re.M,
)
proto_re = re.compile(
    r"^\s*static\s+([A-Za-z0-9_]+(?:\s*\*+)?)\s+([A-Za-z0-9_]+)\s*\([^;)]*\)[^;{]*;",
    re.M,
)

for root, _, files in os.walk(SOURCES):
    for f in files:
        if f.endswith((".x", ".m")):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, ROOT)
            with open(p, "r", encoding="utf-8", errors="ignore") as fp:
                raw = fp.read()
            cleaned = strip_comments_and_strings(raw)
            prototypes = set(m.group(2) for m in proto_re.finditer(cleaned))
            for m in func_def_re.finditer(cleaned):
                func_name = m.group(2)
                def_pos = m.start()
                if func_name in prototypes:
                    continue
                prefix = cleaned[:def_pos]
                call_matches = list(re.finditer(rf"\b{func_name}\s*\(", prefix))
                valid_calls = []
                for cm in call_matches:
                    line_start = prefix.rfind("\n", 0, cm.start()) + 1
                    line = prefix[line_start : prefix.find("\n", cm.start())]
                    if line.strip().startswith("#") or "typedef" in line:
                        continue
                    valid_calls.append(line.strip())
                if valid_calls:
                    log_error(
                        f"In {rel}: static function '{func_name}' is called before definition without forward declaration: {valid_calls[0]}"
                    )

if errors:
    print(f"\n[FAIL] Pre-flight checks failed with {len(errors)} error(s).")
    sys.exit(1)
else:
    print("\n[PASS] All syntax, layer, and logic pre-flight checks passed!")
    sys.exit(0)
