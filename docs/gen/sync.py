#!/usr/bin/env python3
"""Regenerate the parts of the docs site that the binary already knows.

The site's command table, exit codes, env list, version and help.json all come
from `essaim help-json` -- run against the LATEST PUBLISHED RELEASE, not the
local build, because the site's install command downloads that release. A tag
without a GitHub release would otherwise put a version on the site that the
install link does not serve. Hand-copying them is how a docs page drifts: the
in-binary guide once claimed "one static binary" for four releases while the
README said otherwise. So they are generated, and `--check` fails if the
committed site no longer matches the binary.

    docs/gen/sync.py                  # rewrite docs/ from the latest release
    docs/gen/sync.py --check          # exit 1 if docs/ is stale
    docs/gen/sync.py --bin ./essaim   # preview against a local build (do not commit)
"""
import hashlib, html, json, os, re, subprocess, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
REPO = "javimosch/essaim"
ASSET = "essaim-linux-amd64"
CACHE = Path(__file__).resolve().parent / ".cache"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "essaim-docs-sync"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def release_binary():
    rel = json.loads(fetch("https://api.github.com/repos/%s/releases/latest" % REPO))
    tag = rel["tag_name"]
    urls = {a["name"]: a["browser_download_url"] for a in rel["assets"]}
    if ASSET not in urls or ASSET + ".sha256" not in urls:
        sys.exit("sync: release %s is missing %s or its .sha256" % (tag, ASSET))
    path = CACHE / tag / ASSET
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        body = fetch(urls[ASSET])
        want = fetch(urls[ASSET + ".sha256"]).split()[0].decode()
        got = hashlib.sha256(body).hexdigest()
        if got != want:
            sys.exit("sync: %s digest mismatch (%s != %s)" % (tag, got, want))
        path.write_bytes(body)
        os.chmod(path, 0o755)
    return path


def help_json(binary):
    out = subprocess.run([str(binary), "help-json"], capture_output=True, text=True, check=True).stdout
    return json.loads(out)["data"]


def between(text, tag, body):
    pat = re.compile(r"(<!-- gen:%s -->)(.*?)(<!-- /gen:%s -->)" % (tag, tag), re.S)
    if not pat.search(text):
        sys.exit("sync: marker gen:%s missing" % tag)
    return pat.sub(lambda m: m.group(1) + body + m.group(3), text)


def code(s):
    return "<code>%s</code>" % html.escape(s)


def render_index(text, h):
    rows = []
    for name, c in h["commands"].items():
        args = " ".join(code(a) for a in c["args"]) or '<span class="c">—</span>'
        flags = " ".join(code(f) for f in c["flags"]) or '<span class="c">—</span>'
        rows.append('<tr><td>%s</td><td>%s</td><td class="flags">%s</td></tr>' % (code("essaim " + name), args, flags))
    exits = ['<tr><td>%s</td><td>%s</td></tr>' % (code(k), html.escape(v)) for k, v in h["exit_codes"].items()]
    text = between(text, "version", h["version"])
    text = between(text, "commands", "\n" + "\n".join(rows) + "\n")
    text = between(text, "exit", "\n" + "\n".join(exits) + "\n")
    text = between(text, "env", ", ".join(code(e) for e in h["env"]))
    return text


def render_llms(text, h):
    lines = []
    for name, c in h["commands"].items():
        sig = " ".join(["essaim", name] + c["args"] + c["flags"])
        lines.append("- `%s`" % sig)
    exits = ["- `%s` %s" % (k, v) for k, v in h["exit_codes"].items()]
    text = re.sub(r"(Version: )\S+", lambda m: m.group(1) + h["version"], text, count=1)
    text = between(text, "commands", "\n" + "\n".join(lines) + "\n")
    text = between(text, "exit", "\n" + "\n".join(exits) + "\n")
    return text


def main():
    check = "--check" in sys.argv
    if "--bin" in sys.argv:
        binary = Path(sys.argv[sys.argv.index("--bin") + 1]).resolve()
    else:
        binary = release_binary()
    h = help_json(binary)
    print("source: %s (essaim %s)" % (binary, h["version"]))
    wanted = {
        DOCS / "help.json": json.dumps(h, indent=2) + "\n",
        DOCS / "index.html": render_index((DOCS / "index.html").read_text(), h),
        DOCS / "llms.txt": render_llms((DOCS / "llms.txt").read_text(), h),
    }
    stale = [p for p, body in wanted.items() if not p.exists() or p.read_text() != body]
    if check:
        for p in stale:
            print("stale: %s (run docs/gen/sync.py)" % p.relative_to(ROOT))
        sys.exit(1 if stale else 0)
    for p in stale:
        p.write_text(wanted[p])
        print("wrote %s" % p.relative_to(ROOT))
    if not stale:
        print("docs already in sync with essaim %s" % h["version"])


if __name__ == "__main__":
    main()
