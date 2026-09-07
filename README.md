# essaim

An agent-first BitTorrent client. One 144 kB binary, JSON on stdout, no daemon.

Written in [MFL](https://github.com/javimosch/machin) — bencode, the peer wire
protocol, trackers, BEP 9 metadata exchange and SHA-1 verification are all pure
MFL. No libtorrent, no Node, no Python.

```sh
essaim search "apollo 11 audio" --limit 10     # across the enabled indexes
essaim peers  <infohash> --no-trackers         # who is in the swarm, via DHT only
essaim info   ./file.torrent                   # read metadata, download nothing
essaim get    ./file.torrent --dir ./dl        # or a magnet, or a https URL
essaim info   "magnet:?xt=urn:btih:…" --fetch  # list the files, download nothing
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
| **DHT** | BEP 5 Kademlia — a bare magnet with no trackers works |
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
- **DHT**: 56 peers found for a busy swarm with trackers *fully disabled*, and a
  bare trackerless magnet resolved its full 15-file listing via DHT → BEP 9
- `machin build --race-safe` passes: the engine is **proved** data-race free

## Search sources

Sources are **config rows, not code** — adding one is a table entry in
[`src/indexer.src`](src/indexer.src): a URL template, how to walk the response,
and where the fields live.

**Only archive.org is enabled out of the box.** The other rows ship *disabled*
and exist as worked examples of the two supported response shapes — flip
`enabled` to `1`, or add your own row, and rebuild.

| source | kind | category | default |
|---|---|---|---|
| archive.org | JSON (`.torrent` links) | all | **enabled** |
| others (6) | JSON / RSS examples | various | disabled |

Enable a disabled row for one run without rebuilding:

```sh
essaim search "hitman" --cat games --source piratebay-games
ESSAIM_SOURCES=all essaim search "…"
```

Two response shapes cover every index worth querying: a JSON API addressed by
path templates (`{i}` = row index) and an RSS feed split on `<item>` and read
with regexes. A source that errors is skipped with a note on stderr — one dead
index must not sink a search. Rows marked `filter: "local"` return a firehose
regardless of the query, so essaim narrows them itself.

`essaim sources` lists what is compiled in and which rows are live.

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
./tests/run.sh  # 228 assertions across 9 suites
```

Tests need no network: the tracker suite stands up a fake BEP 15 tracker, the
engine suite stands up a real seeder speaking the actual peer protocol, and the
index suite parses recorded response fixtures.

## Limits

- **Leech only.** No seeding, no `watch`, no `serve` yet.
- The DHT is intermittent by nature: a lookup takes a few rounds and can come up
  empty on a quiet swarm, so a retry is normal. `--no-dht` turns it off.
- Search sources are third-party indexes and go stale; `essaim sources` lists
  what is compiled in and which rows are enabled.

## Status and disclaimer

essaim is an **experiment**: it exists to dogfood
[machin](https://github.com/javimosch/machin) by building something demanding in
it — a real binary protocol, real concurrency, real network failure modes — and
it drove two additions into the language along the way (`udp_socket` /
`udp_sendto` / `udp_recvfrom` and `write_file_at`).

It is provided as-is, with **no warranty and no responsibility taken for how it
is used or for anything any third-party index returns**. You are responsible for
what you download and for complying with the law and the terms of any service you
point it at. See the MIT licence.

## Credits

Designed and written with [Claude Code](https://claude.com/claude-code), which
holds authorship of essentially all of this repository — the protocol
implementations, the test suites, and the machin language changes underneath it.

## Licence

MIT — see [LICENSE](LICENSE).
