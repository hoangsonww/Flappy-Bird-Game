#!/usr/bin/env python3
"""Fail if anything in the docs or the landing page points at something missing.

Checks, across every tracked Markdown file, ``index.html`` and ``sitemap.xml``:

* relative links and images resolve to a file that exists;
* in-page anchors (``#heading``) match a real heading, using GitHub's slug rules;
* every screenshot the landing page, the sitemap and the web manifest advertise
  is in the repo;
* the JSON-LD block parses, and its FAQ questions match the visible ones.
* the landing page's repository statistics match the source tree.

Run it with ``make check-links``. It takes about a second and needs nothing but
the standard library, which is why it runs in CI on every push.
"""

from __future__ import annotations

import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {"node_modules", ".git", "build", "DerivedData", "coverage", "dist"}

problems: list[str] = []


def report(where: str, message: str) -> None:
    problems.append(f"{where}: {message}")


# ── Markdown ─────────────────────────────────────────────────────────────────

LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HTML_IMG = re.compile(r"<img[^>]+src=\"([^\"]+)\"")
HEADING = re.compile(r"(#{1,6})\s+(.*)")


def slug(text: str) -> str:
    """GitHub's heading slug: strip markup, drop punctuation, spaces to hyphens."""
    text = re.sub(r"`", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text)
    return text.replace(" ", "-")


_slugs: dict[str, set[str]] = {}


def slugs_of(path: str) -> set[str]:
    if path in _slugs:
        return _slugs[path]
    found: set[str] = set()
    fenced = False
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("```"):
                fenced = not fenced
                continue
            if fenced:
                continue
            match = HEADING.match(line)
            if match:
                found.add(slug(match.group(2).strip()))
    _slugs[path] = found
    return found


def markdown_files() -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        out += [os.path.join(dirpath, f) for f in filenames if f.endswith(".md")]
    # .github holds CONTRIBUTING, SECURITY and the templates.
    for dirpath, _, filenames in os.walk(os.path.join(ROOT, ".github")):
        out += [os.path.join(dirpath, f) for f in filenames if f.endswith(".md")]
    return sorted(set(out))


def check_markdown() -> int:
    files = markdown_files()
    for path in files:
        rel = os.path.relpath(path, ROOT)
        base = os.path.dirname(path)
        text = open(path, encoding="utf-8").read()
        targets = LINK.findall(text) + HTML_IMG.findall(text)
        for target in targets:
            if target.startswith(("http://", "https://", "mailto:", "data:")):
                continue
            if target.startswith("#"):
                if target[1:].lower() not in slugs_of(path):
                    report(rel, f"anchor {target} matches no heading")
                continue
            path_part, _, fragment = target.partition("#")
            resolved = os.path.normpath(os.path.join(base, path_part))
            if not os.path.exists(resolved):
                report(rel, f"link {target} points at a missing file")
            elif fragment and resolved.endswith(".md"):
                if fragment.lower() not in slugs_of(resolved):
                    report(rel, f"anchor {target} matches no heading in {path_part}")
    return len(files)


# ── Landing page ─────────────────────────────────────────────────────────────


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.images: list[str] = []
        self.hrefs: list[str] = []
        self.ids: set[str] = set()
        self.jsonld: list[str] = []
        self.summaries: list[str] = []
        self._in_jsonld = False
        self._in_summary = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "img" and values.get("src"):
            self.images.append(values["src"])
        if tag in {"link"} and values.get("href"):
            self.hrefs.append(values["href"])
        if tag == "a" and values.get("href"):
            self.hrefs.append(values["href"])
        if tag == "script" and values.get("type") == "application/ld+json":
            self._in_jsonld = True
        if tag == "summary":
            self._in_summary = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "script":
            self._in_jsonld = False
        if tag == "summary":
            self._in_summary = False

    def handle_data(self, data: str) -> None:
        if self._in_jsonld:
            self.jsonld.append(data)
        if self._in_summary:
            self.summaries.append(data.strip())


def check_landing_page() -> None:
    path = os.path.join(ROOT, "index.html")
    page = Page()
    page.feed(open(path, encoding="utf-8").read())

    for src in page.images:
        if src.startswith(("http", "data:")):
            continue
        if not os.path.exists(os.path.join(ROOT, src)):
            report("index.html", f"<img src=\"{src}\"> is missing from the repository")

    for href in page.hrefs:
        if href.startswith("#") and len(href) > 1 and href[1:] not in page.ids:
            report("index.html", f"anchor {href} matches no element id")

    if not page.jsonld:
        report("index.html", "no JSON-LD block")
        return

    try:
        graph = json.loads("".join(page.jsonld))
    except json.JSONDecodeError as error:
        report("index.html", f"JSON-LD does not parse: {error}")
        return

    nodes = graph.get("@graph", [graph])
    types = {node.get("@type") for node in nodes}
    for required in ("WebSite", "VideoGame", "SoftwareSourceCode", "FAQPage"):
        if required not in types:
            report("index.html", f"JSON-LD is missing a {required} entity")

    faq = next((n for n in nodes if n.get("@type") == "FAQPage"), None)
    if faq:
        asked = [q.get("name", "") for q in faq.get("mainEntity", [])]
        if asked != page.summaries[: len(asked)]:
            report(
                "index.html",
                "the FAQ questions in JSON-LD do not match the visible <summary> text",
            )


def count_test_functions(directory: str) -> int:
    """Count XCTest methods without needing Xcode on the Linux CI site job."""
    total = 0
    root = os.path.join(ROOT, directory)
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            if filename.endswith(".swift"):
                text = open(os.path.join(dirpath, filename), encoding="utf-8").read()
                total += len(re.findall(r"^\s*func test", text, flags=re.MULTILINE))
    return total


def check_project_facts() -> None:
    """Keep the most visible numeric claims tied to the files they describe."""
    swift_sources = sum(
        filename.endswith(".swift")
        for _, _, filenames in os.walk(os.path.join(ROOT, "FlappyBird"))
        for filename in filenames
    )
    unit_tests = count_test_functions("FlappyBirdTests")
    ui_tests = count_test_functions("FlappyBirdUITests")

    backend_tests = 0
    tests_root = os.path.join(ROOT, "backend", "tests")
    for dirpath, _, filenames in os.walk(tests_root):
        for filename in filenames:
            if filename.endswith((".test.ts", ".spec.ts")):
                text = open(os.path.join(dirpath, filename), encoding="utf-8").read()
                backend_tests += len(re.findall(r"\b(?:it|test)\s*\(", text))

    achievements_path = os.path.join(
        ROOT, "FlappyBird", "Systems", "AchievementSystem.swift"
    )
    achievements = open(achievements_path, encoding="utf-8").read().count(
        "Achievement(code:"
    )
    total_tests = unit_tests + ui_tests + backend_tests

    expected = {
        "tests passing": total_tests,
        "Swift sources": swift_sources,
        "achievements": achievements,
    }
    html = open(os.path.join(ROOT, "index.html"), encoding="utf-8").read()
    published = re.findall(
        r'data-count="(\d+)">(?:\d+)</b><span>([^<]+)</span>', html
    )
    for raw_value, label in published:
        if label in expected and int(raw_value) != expected[label]:
            report(
                "index.html",
                f"{label} says {raw_value}; the repository contains {expected[label]}",
            )

    claims = {
        "README.md": [
            f"{total_tests} tests run on every push",
            f"make test     # {unit_tests} Swift unit tests",
            f"make test-ui  # {ui_tests} Swift UI tests",
        ],
        "docs/TESTING.md": [
            f"{total_tests} tests: **{unit_tests} Swift unit**, "
            f"**{ui_tests} Swift UI** and **{backend_tests} backend**"
        ],
    }
    for relative, required in claims.items():
        text = open(os.path.join(ROOT, relative), encoding="utf-8").read()
        for claim in required:
            if claim not in text:
                report(relative, f"missing current generated fact: {claim}")


# ── Sitemap and robots ───────────────────────────────────────────────────────

SITE = "https://hoangsonww.github.io/Flappy-Bird-Game/"


def check_sitemap() -> None:
    path = os.path.join(ROOT, "sitemap.xml")
    if not os.path.exists(path):
        report("sitemap.xml", "missing")
        return
    try:
        tree = ET.parse(path)
    except ET.ParseError as error:
        report("sitemap.xml", f"does not parse: {error}")
        return

    urls = [element.text or "" for element in tree.iter() if element.tag.endswith("}loc")]
    if not urls:
        report("sitemap.xml", "lists no URLs")

    for url in urls:
        if not url.startswith(SITE):
            report("sitemap.xml", f"{url} is not under {SITE}")
            continue
        relative = url[len(SITE):]
        if not relative:
            continue  # the page itself
        if not os.path.exists(os.path.join(ROOT, relative)):
            report("sitemap.xml", f"{relative} is advertised but not in the repository")

    robots = os.path.join(ROOT, "robots.txt")
    if not os.path.exists(robots):
        report("robots.txt", "missing")
    elif f"Sitemap: {SITE}sitemap.xml" not in open(robots, encoding="utf-8").read():
        report("robots.txt", "does not point at the sitemap")


def check_manifest() -> None:
    path = os.path.join(ROOT, "site.webmanifest")
    if not os.path.exists(path):
        report("site.webmanifest", "missing")
        return
    try:
        manifest = json.load(open(path, encoding="utf-8"))
    except json.JSONDecodeError as error:
        report("site.webmanifest", f"does not parse: {error}")
        return

    assets = manifest.get("icons", []) + manifest.get("screenshots", [])
    if not manifest.get("icons"):
        report("site.webmanifest", "declares no icons")
    for asset in assets:
        src = asset.get("src", "")
        if not os.path.exists(os.path.join(ROOT, src)):
            report("site.webmanifest", f"{src} is declared but not in the repository")


def main() -> int:
    count = check_markdown()
    check_landing_page()
    check_project_facts()
    check_sitemap()
    check_manifest()

    if problems:
        print(f"✖ {len(problems)} problem(s):\n")
        for problem in problems:
            print(f"  {problem}")
        return 1

    print(
        f"✓ {count} Markdown files, index.html, sitemap.xml and site.webmanifest "
        "— every reference resolves"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
