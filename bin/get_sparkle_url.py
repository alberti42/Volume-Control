#!/usr/bin/env python3
"""
Prints the browser_download_url for Sparkle-for-Swift-Package-Manager.zip
from the latest Sparkle GitHub release (reads JSON from stdin).
"""
import sys
import json

assets = json.load(sys.stdin)["assets"]
url = next(
    (a["browser_download_url"] for a in assets if "Swift-Package-Manager" in a["name"]),
    None,
)
if not url:
    raise SystemExit("ERROR: Sparkle-for-Swift-Package-Manager.zip not found in latest release")
print(url)
