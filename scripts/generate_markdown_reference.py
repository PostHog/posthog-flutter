"""Generate the SDK reference Markdown from the doc comments with `dart doc`.

`dart doc` (part of the Dart SDK) writes one HTML page per symbol and an index.json that lists every
symbol with its kind and enclosing type. BeautifulSoup reads each page's signature and description,
and markdownify turns the description into Markdown. Our code only groups Posthog members by the
sdk-specs capability docs/capabilities.json gives them, in the PostHog/sdk-specs README's order, and
writes front matter. Members it lists under `utils` go to SDK utils.

    pip install -r scripts/requirements.txt
    python3 scripts/generate_markdown_reference.py --sdk-specs DIR [--major 6]
"""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from bs4 import BeautifulSoup
from markdownify import markdownify

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "posthog_flutter"
LIBRARY = "posthog_flutter"
FIRST = ["setup", "capture", "identify"]
# Public client classes get their own H2; every other public type goes in Types.
CLIENTS = "PostHogLogger PosthogObserver PostHogWidget PostHogMaskWidget PostHogUnmaskWidget PostHogPlatformView PostHogIsolateExtension".split()
# dartdoc's index.json kinds.
CONSTRUCTOR, CLASS, ENUM, EXTENSION, FUNCTION, METHOD, PROPERTY, TYPEDEF = 2, 3, 5, 6, 8, 10, 16, 21
KEYWORD = {CLASS: "class", ENUM: "enum", EXTENSION: "extension"}
# Members every Dart object has, which say nothing about the SDK.
OBJECT = {"hashCode", "toString", "noSuchMethod", "runtimeType", "operator =="}
MDX = str.maketrans({"{": "&#123;", "}": "&#125;"})  # MDX 1 reads braces as JSX


class Docs:
    def __init__(self, out: Path):
        self.out = out
        self.index = json.loads((out / "index.json").read_text())

    def page(self, symbol: dict):
        html = (self.out / symbol["href"].split("#")[0]).read_text()
        return BeautifulSoup(html, "html.parser").select_one("#dartdoc-main-content")

    def members(self, symbol: dict) -> list[dict]:
        """What a type declares itself: constructors, properties and methods, without overrides."""
        return [
            s for s in self.index
            if s.get("enclosedBy", {}).get("href") == symbol["href"] and s["kind"] in (CONSTRUCTOR, PROPERTY, METHOD)
            and not s.get("overriddenDepth") and s["name"] not in OBJECT
        ]

    def entry(self, symbol: dict, label: str, level: int) -> str:
        page = self.page(symbol)
        sig = page.select_one("section.multi-line-signature")
        for feature in sig.select(".features") if sig else []:  # "final", "getter/setter pair"
            feature.decompose()
        code = tidy(" ".join(sig.get_text().split())) if sig else f"{KEYWORD.get(symbol['kind'], '')} {symbol['name']}".strip()
        parts = [f"{'#' * level} `{label}`", f"```dart\n{code}\n```"]
        parts += [markdown(page.select_one(s)) for s in ("section.desc", "section#values") if page.select_one(s)]
        return "\n\n".join(p for p in parts if p)


def tidy(signature: str) -> str:
    """Drops the spaces dartdoc's line breaks leave just inside brackets and before a closing one."""
    for a, b in (("( ", "("), (" )", ")"), ("{ ", "{"), (", }", "}"), (", )", ")"), ("[ ", "["), (", ]", "]")):
        signature = signature.replace(a, b)
    return signature


def markdown(node) -> str:
    """A dartdoc section as Markdown. Links become plain text."""
    for dl in node.select("dl"):  # enum values and properties become `name: description` lists
        items = [(dt.select_one(".name") or dt).get_text().strip() for dt in dl.select("dt")]
        docs = [(dd.p or dd).decode_contents() for dd in dl.select("dd")]
        dl.replace_with(BeautifulSoup("<ul>" + "".join(f"<li><code>{n}</code>: {d}</li>" for n, d in zip(items, docs)) + "</ul>", "html.parser"))
    for h in node.find_all(["h2", "h3"]):
        h.name = "h5"
    for text in node.find_all(string=True):  # braces in prose only; code keeps them
        if not text.find_parent(["code", "pre"]):
            text.replace_with(str(text).translate(MDX))
    md = markdownify(str(node), strip=["a"], heading_style="ATX", bullets="-", code_language="dart")
    return md.strip().replace("<br>", "<br />")


def capabilities(checkout: str) -> dict[str, str]:
    """Each sdk-specs capability's slug and title in sentence case, in the README's order."""
    acronyms = {"id": "ID", "ai": "AI", "http": "HTTP", "mcp": "MCP"}
    titles = {}
    for line in (Path(checkout) / "README.md").read_text().split("\n"):
        cells = line.split("|")
        if len(cells) > 2 and "openspec/specs/" in cells[2]:
            slug = cells[2].split("openspec/specs/")[1].split("/")[0]
            titles[slug] = " ".join(acronyms.get(w.lower(), w.lower()) for w in cells[1].split())
    order = [*FIRST, *(s for s in titles if s not in FIRST)]
    return {s: titles[s][0].upper() + titles[s][1:] for s in order if s in titles}


def reference(docs: Docs, caps: dict[str, str], current: bool) -> list[str]:
    top = sorted(
        (s for s in docs.index if s.get("enclosedBy", {}).get("name") == LIBRARY and s["kind"] in (CLASS, ENUM, EXTENSION, TYPEDEF, FUNCTION)),
        key=lambda s: s["name"],
    )
    sdk = next(s for s in top if s["name"] == "Posthog")
    mapped = json.loads((ROOT / "docs/capabilities.json").read_text())
    listed, upcoming = set(mapped.pop("utils")), mapped.pop("next", {})
    members = {f"Posthog.{m['name']}": m for m in docs.members(sdk)}
    for name in mapped if current else []:  # the next major may remove methods
        if name not in members:
            raise SystemExit(f"docs/capabilities.json: {name} is not a Posthog member")
    mapped |= upcoming
    tagged: dict[str, list[str]] = {}
    utils = []
    for name, m in members.items():
        found = mapped.get(name)
        if found and found not in caps:
            raise SystemExit(f"docs/capabilities.json: {name} has unknown capability {found}")
        if not found and name not in listed:
            raise SystemExit(f"docs/capabilities.json: map {name} to a capability or list it in utils")
        (tagged.setdefault(found, []) if found else utils).append(docs.entry(m, name, 3))
    out = []
    for slug, title in caps.items():
        if slug in tagged:
            out += [f"## {title}", *tagged[slug]]
    out += ["## SDK utils", *utils]
    for name in sorted(CLIENTS):
        client = next(s for s in top if s["name"] == name)
        out += [f"## {name}", docs.entry(client, name, 3)]
        out += [docs.entry(m, label(name, m), 4) for m in docs.members(client)]
    out.append("## Types")
    for t in top:
        if t["name"] not in CLIENTS and t is not sdk:
            out.append(docs.entry(t, t["name"], 3))
            out += [docs.entry(m, label(t["name"], m), 4) for m in docs.members(t)]
    return out


def label(owner: str, member: dict) -> str:
    """`Type.member`, or `Type()` and `Type.named` for constructors, which dartdoc names `Type.new`."""
    if member["kind"] == CONSTRUCTOR:
        return f"{owner}()" if member["name"].endswith(".new") else member["name"]
    return f"{owner}.{member['name']}"


def anchor(heading: str) -> str:
    """The github-slugger slug the docs site gives a heading."""
    return "".join(c for c in heading.lower() if c.isalnum() or c in "-_ ").replace(" ", "-")


def front_matter(title: str, sections: list[str]) -> str:
    """The docs site's front matter. Its ToC lists the page's H2 sections only."""
    toc = []
    for heading in [s[3:] for s in sections if s.startswith("## ")]:
        toc.append(f'  - value: "{heading}"\n    url: {anchor(heading)}\n    depth: 0')
    head = [f'title: "{title}"', "sidebar: Docs", "showTitle: true"]
    head += ["contentMaxWidthClass: max-w-full", "platformLogo: flutter", "tableOfContents:", *toc]
    return "\n".join(["---", *head, "---"])


def nest(markdown: str) -> str:
    """Moves each heading down one level and drops the H1. Code stays as written."""
    out, fence = [], False
    for line in markdown.strip().split("\n"):
        fence ^= line.strip().startswith("```")
        if fence or not line.startswith("#"):
            out.append(line)
        elif not line.startswith("# "):
            out.append("#" + line)
    return "\n".join(out)


def write(name: str, sections: list[str]) -> None:
    (ROOT / "references" / name).write_text("\n\n".join(sections) + "\n")
    print(f"wrote references/{name}")


def main() -> None:
    args = argparse.ArgumentParser(description="Generate the SDK reference Markdown.")
    args.add_argument("--sdk-specs", required=True, help="PostHog/sdk-specs checkout")
    args.add_argument("--major", type=int, help="target major, defaults to the declared one")
    opts = args.parse_args()
    version = next(l for l in (PKG / "pubspec.yaml").read_text().split("\n") if l.startswith("version:"))
    declared = int(version.split(":")[1].strip().split(".")[0])
    major = opts.major or declared
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["flutter", "pub", "get"], cwd=PKG, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["dart", "doc", "--output", tmp], cwd=PKG, check=True, stdout=subprocess.DEVNULL)
        docs = Docs(Path(tmp))
        body = ["## Getting started", nest((ROOT / "docs/getting-started.md").read_text())]
        body += reference(docs, capabilities(opts.sdk_specs), declared >= major)
    (ROOT / "references").mkdir(exist_ok=True)
    title = f"PostHog Flutter SDK {major}.x" + ("" if declared >= major else " (experimental)")
    write(f"posthog-flutter-{major}.md", [front_matter(title, body), *body])
    if declared >= major:
        write("posthog-flutter-reference.md", [front_matter("PostHog Flutter SDK", body), *body])
    # The migration guide lives next to the package, as posthog_flutter/MIGRATION.md.
    if guides := [g for g in [PKG / "MIGRATION.md"] if g.exists()]:
        head = "---\ntitle: PostHog Flutter SDK migration guides\nsidebar: Docs\nshowTitle: true\n---"
        write("posthog-flutter-migration.md", [head, *(g.read_text().strip() for g in guides)])


if __name__ == "__main__":
    main()
