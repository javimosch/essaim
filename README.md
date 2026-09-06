# essaim

An agent-first BitTorrent client. One 144 kB binary, JSON on stdout, no daemon.

Written in [MFL](https://github.com/javimosch/machin) — bencode, the peer wire
protocol, trackers, BEP 9 metadata exchange and SHA-1 verification are all pure
MFL. No libtorrent, no Node, no Python.

```sh
essaim search "apollo 11 audio" --limit 10     # across five indexes at once
essaim info   ./file.torrent                   # read metadata, download nothing
essaim get    ./file.torrent --dir ./dl        # or a magnet, or a https URL
essaim guide                                   # the whole mental model, embedded
```

Progress goes to stderr and the result to stdout, so `essaim get … | jq` works
while you still watch it run. Exit codes are semantic: `0` complete, `105`
incomplete (rerun to resume), `100` no peers, `82` bad input — and the code
always equals `error.code` in the body.

## What it does

| | |
|---|---|
| **Trackers** | UDP (BEP 15) and HTTP (BEP 3) |
| **Peers** | BEP 3 wire protocol, 16 KiB blocks pipelined per piece |
| **Magnets** | BEP 9 metadata exchange over the BEP 10 extension protocol |
| **Verification** | nothing is believed until a piece's SHA-1 matches the torrent's commitment |
| **Resume** | no progress journal — the files on disk *are* the state |
| **Search** | five indexes, each a declarative config row |

## Live-verified

- A 5.5 MB, 13-file torrent (UTF-8 Korean filenames) from a real swarm in 3.3 s;
  all 11 pieces independently re-checked against the `.torrent`
- The same content via **magnet** — BEP 9 metadata from a live peer, then
  `diff -r` against the `.torrent` download: **no differences**
- Full loop: `search` → 7.2 MB archive.org item → `get` → 14/14 pieces in 6.4 s
  → `unzip -t` reports no errors
- `machin build --race-safe` passes: the engine is **proved** data-race free

## Search sources

Sources are **config rows, not code** — adding one is a table entry in
[`src/indexer.src`](src/indexer.src): a URL template, how to walk the response,
and where the fields live.

| source | kind | category |
|---|---|---|
| piratebay | JSON | all |
| archive.org | JSON (`.torrent` links) | all |
| yts | JSON | movies |
| eztv | JSON | tv |
| nyaa | RSS | anime |
| subsplease | RSS | anime |

Two response shapes cover all of them: a JSON API addressed by path templates
(`{i}` = row index) and an RSS feed split on `<item>` and read with regexes.
A source that errors is skipped with a note on stderr — one dead index must not
sink a search. Sources marked `filter: "local"` return a firehose (EZTV filters
only by IMDb id; SubsPlease has no query at all), so essaim narrows those rows
itself.

## Agent-first conventions

Follows the [cli-specs](https://cli-specs.intrane.fr/) family:

| spec | status |
|---|---|
| cli-output-spec | stdout=data, stderr=context, semantic exit codes, typed errors, `help-json` |
| cli-guide-spec | `essaim guide` — model, loop, concepts, gotchas, embedded in the binary |
| cli-update-spec | `essaim update` (content-hash + smoke test + `.bak`), `install`/`uninstall` |
| cli-feedback-spec | `essaim feedback "…" --kind bug` — dual-write with an idempotency key |
| cli-telemetry-spec | **deliberately not adopted** (see below) |
| cli-daemon-spec | not yet — `get` is foreground |

**No telemetry, on purpose.** cli-telemetry-spec §8.1 says a tool that cannot
satisfy the must-not-send list for its domain should ship none. For a BitTorrent
client the signal is weak and the trust cost is high: what someone downloads is
exactly what usage data must never touch. There is nothing to opt out of.

## Install

```sh
curl -fsSL -o essaim <release-url>/essaim-linux-amd64
chmod +x essaim && ./essaim install     # relocates to ~/.local/bin, no sudo
```

Linux x86-64, **glibc 2.34+**, dynamically linked against OpenSSL 3
(`libssl.so.3`, `libcrypto.so.3`). A fully static build is blocked on static
OpenSSL archives for musl.

## Build

```sh
./build.sh      # machin encode src/*.src > essaim.mfl && machin build essaim.mfl
./tests/run.sh  # 181 assertions across 8 suites
```

Tests need no network: the tracker suite stands up a fake BEP 15 tracker, the
engine suite stands up a real seeder speaking the actual peer protocol, and the
index suite parses recorded response fixtures.

## Limits

- **No DHT.** A magnet must list trackers (`&tr=`), or there is nowhere to find
  peers.
- **Leech only.** No seeding, no `watch`, no `serve` yet.
- Search sources are third-party indexes and go stale; `essaim sources` lists
  what is compiled in.

## Licence

MIT.
