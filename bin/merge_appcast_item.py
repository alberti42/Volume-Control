#!/usr/bin/env python3
"""
merge_appcast_item.py  NEW_APPCAST  ORIGINAL_APPCAST

Finds the <item> in NEW_APPCAST whose <sparkle:version> does not appear in
ORIGINAL_APPCAST and prepends it to ORIGINAL_APPCAST.

The result is written back to ORIGINAL_APPCAST.
"""

import sys
import re

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} NEW_APPCAST ORIGINAL_APPCAST", file=sys.stderr)
    sys.exit(1)

new_appcast_path, original_appcast_path = sys.argv[1], sys.argv[2]

with open(new_appcast_path, encoding="utf-8") as f:
    new_content = f.read()

with open(original_appcast_path, encoding="utf-8") as f:
    original_content = f.read()

item_re = re.compile(r"<item>.*?</item>", re.DOTALL)

# Collect build numbers already present in the original appcast
original_builds = set(re.findall(r"<sparkle:version>(\d+)</sparkle:version>", original_content))

# Find the new item — the one whose build is not in the original
new_item = next(
    (m.group(0) for m in item_re.finditer(new_content)
     if re.search(r"<sparkle:version>(\d+)</sparkle:version>", m.group(0)) and
        re.search(r"<sparkle:version>(\d+)</sparkle:version>", m.group(0)).group(1)
        not in original_builds),
    None,
)

if not new_item:
    print("ERROR: no new <item> found in new appcast that is absent from original", file=sys.stderr)
    sys.exit(1)

build = re.search(r"<sparkle:version>(\d+)</sparkle:version>", new_item).group(1)

# Prepend the new item before the first <item> in the original appcast
if "<item>" in original_content:
    original_content = original_content.replace("<item>", new_item + "\n        <item>", 1)
else:
    original_content = original_content.replace("</channel>", f"        {new_item}\n    </channel>")

with open(original_appcast_path, "w", encoding="utf-8") as f:
    f.write(original_content)

print(f"Merged build {build} into {original_appcast_path}.")
