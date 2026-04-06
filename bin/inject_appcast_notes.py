#!/usr/bin/env python3
"""
inject_appcast_notes.py  APPCAST_PATH  NOTES_HTML_PATH

Injects the contents of NOTES_HTML_PATH as a <description><![CDATA[...]]></description>
element into the FIRST <item> in APPCAST_PATH (which is always the newest release).
"""

import sys
import re

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} APPCAST_PATH NOTES_HTML_PATH", file=sys.stderr)
    sys.exit(1)

appcast_path, notes_path = sys.argv[1], sys.argv[2]

with open(notes_path, encoding="utf-8") as f:
    notes_html = f.read().strip()

with open(appcast_path, encoding="utf-8") as f:
    content = f.read()

desc_tag = "<description><![CDATA[\n" + notes_html + "\n            ]]></description>"

item_re = re.compile(r"(<item>.*?)(</item>)", re.DOTALL)

first_match = item_re.search(content)
if not first_match:
    print("ERROR: no <item> found in appcast", file=sys.stderr)
    sys.exit(1)

def inject(m):
    inner = m.group(1)
    if "<description>" in inner:
        inner = re.sub(r"<description>.*?</description>", desc_tag, inner, flags=re.DOTALL)
    else:
        inner += "\n            " + desc_tag + "\n        "
    return inner + m.group(2)

# Replace only the first item
new_content = item_re.sub(inject, content, count=1)

build = re.search(r"<sparkle:version>(\d+)</sparkle:version>", first_match.group(0))
build_str = build.group(1) if build else "unknown"

with open(appcast_path, "w", encoding="utf-8") as f:
    f.write(new_content)

print(f"Release notes injected into first item (build {build_str}).")
