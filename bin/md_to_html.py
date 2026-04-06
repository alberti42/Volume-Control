#!/usr/bin/env python3
"""
md_to_html.py  INPUT_MD  OUTPUT_HTML

Converts a GitHub-flavored Markdown file to an HTML fragment
suitable for Sparkle release notes (no external dependencies).

Handles: headings, bold, italic, inline code, links, bullet lists,
         numbered lists, horizontal rules, and paragraphs.
"""

import re
import sys

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} INPUT_MD OUTPUT_HTML", file=sys.stderr)
    sys.exit(1)

with open(sys.argv[1], encoding="utf-8") as f:
    lines = f.readlines()


def inline(text):
    """Convert inline Markdown to HTML."""
    # Bold + italic
    text = re.sub(r"\*\*\*(.*?)\*\*\*", r"<strong><em>\1</em></strong>", text)
    # Bold
    text = re.sub(r"\*\*(.*?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"__(.*?)__", r"<strong>\1</strong>", text)
    # Italic
    text = re.sub(r"\*(.*?)\*", r"<em>\1</em>", text)
    text = re.sub(r"_(.*?)_", r"<em>\1</em>", text)
    # Inline code
    text = re.sub(r"`(.*?)`", r"<code>\1</code>", text)
    # Links
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


html_lines = []
in_ul = False
in_ol = False
in_p = False
paragraph = []


def flush_paragraph():
    global in_p, paragraph
    if paragraph:
        html_lines.append(f"<p>{inline(' '.join(paragraph))}</p>")
        paragraph = []
        in_p = False


def close_list():
    global in_ul, in_ol
    if in_ul:
        html_lines.append("</ul>")
        in_ul = False
    if in_ol:
        html_lines.append("</ol>")
        in_ol = False


for line in lines:
    line = line.rstrip("\n")

    # Heading
    m = re.match(r"^(#{1,6})\s+(.*)", line)
    if m:
        flush_paragraph()
        close_list()
        level = len(m.group(1))
        html_lines.append(f"<h{level}>{inline(m.group(2))}</h{level}>")
        continue

    # Horizontal rule
    if re.match(r"^[-*_]{3,}\s*$", line):
        flush_paragraph()
        close_list()
        html_lines.append("<hr>")
        continue

    # Unordered list item
    m = re.match(r"^[\-\*\+]\s+(.*)", line)
    if m:
        flush_paragraph()
        if in_ol:
            close_list()
        if not in_ul:
            html_lines.append("<ul>")
            in_ul = True
        html_lines.append(f"<li>{inline(m.group(1))}</li>")
        continue

    # Ordered list item
    m = re.match(r"^\d+\.\s+(.*)", line)
    if m:
        flush_paragraph()
        if in_ul:
            close_list()
        if not in_ol:
            html_lines.append("<ol>")
            in_ol = True
        html_lines.append(f"<li>{inline(m.group(1))}</li>")
        continue

    # Blank line
    if line.strip() == "":
        flush_paragraph()
        close_list()
        continue

    # Regular text — accumulate into paragraph
    close_list()
    paragraph.append(line.strip())

flush_paragraph()
close_list()

with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("\n".join(html_lines) + "\n")
