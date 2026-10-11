#!/usr/bin/env python3
"""
changelog.py — Maintain CHANGELOG.md in the Keep a Changelog 1.1.0 format.

Usage:
  bin/changelog.py release X.Y.Z [YYYY-MM-DD]   Move the [Unreleased] entries under
                                                "## [X.Y.Z] - date", open a new empty
                                                [Unreleased] and update the links.
  bin/changelog.py section X.Y.Z|Unreleased     Print the body of one section.

No external dependencies.
"""

import datetime
import pathlib
import re
import sys

CHANGELOG = pathlib.Path(__file__).resolve().parent.parent / "CHANGELOG.md"
REPO_URL = "https://github.com/alberti42/Volume-Control"

HEADING = re.compile(r"^## \[([^\]]+)\]", re.M)


def section_body(text, name):
    """Return the text between '## [name]' and the next '## [' heading or link list."""
    m = re.search(rf"^## \[{re.escape(name)}\][^\n]*\n", text, re.M)
    if not m:
        return None
    rest = text[m.end():]
    end = re.search(r"^## \[|^\[[^\]]+\]: ", rest, re.M)
    return (rest[: end.start()] if end else rest).strip("\n")


def release(text, version, date):
    if re.search(rf"^## \[{re.escape(version)}\]", text, re.M):
        sys.exit(f"Error: CHANGELOG.md already has a section for {version}.")
    body = section_body(text, "Unreleased")
    if body is None:
        sys.exit("Error: CHANGELOG.md has no '## [Unreleased]' section.")
    if not body.strip():
        sys.exit("Error: the [Unreleased] section of CHANGELOG.md is empty; "
                 "describe the changes of this release there first.")

    text = text.replace("## [Unreleased]\n", f"## [Unreleased]\n\n## [{version}] - {date}\n", 1)

    link = re.search(rf"^\[Unreleased\]: {re.escape(REPO_URL)}/compare/(v[^.\s]+\.[^.\s]+\.[^.\s]+)\.\.\.HEAD$",
                     text, re.M)
    if not link:
        sys.exit("Error: could not find the '[Unreleased]: .../compare/vX.Y.Z...HEAD' link.")
    previous = link.group(1)
    text = text.replace(
        link.group(0),
        f"[Unreleased]: {REPO_URL}/compare/v{version}...HEAD\n"
        f"[{version}]: {REPO_URL}/compare/{previous}...v{version}",
        1,
    )
    return text


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("release", "section"):
        sys.exit(__doc__.strip())
    text = CHANGELOG.read_text()
    if sys.argv[1] == "release":
        version = sys.argv[2]
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            sys.exit("Error: release takes a final version X.Y.Z; pre-releases stay under [Unreleased].")
        date = sys.argv[3] if len(sys.argv) > 3 else datetime.date.today().isoformat()
        CHANGELOG.write_text(release(text, version, date))
        print(f"CHANGELOG.md: [Unreleased] moved to [{version}] - {date}.")
    else:
        body = section_body(text, sys.argv[2])
        if body is None:
            sys.exit(f"Error: CHANGELOG.md has no section [{sys.argv[2]}].")
        print(body)


if __name__ == "__main__":
    main()
