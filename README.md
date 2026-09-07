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
essaim seed   ./file.torrent --dir ./dl --up-limit 500   # share, capped
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
| **Seeding** | opt-in, with a **global** upload cap in KB/s |
| **Search** | indexes as declarative config rows |

## Live-verified

- A 5.5 MB, 13-file torrent (UTF-8 Korean filenames) from a real swarm in 3.3 s;
  all 11 pieces independently re-checked against the `.torrent`
- The same content via **magnet** — BEP 9 metadata from a live peer, then
  `diff -r` against the `.torrent` download: **no differences**
- Full loop: `search` → 7.2 MB archive.org item → `get` → 14/14 pieces in 6.4 s
  → `unzip -t` reports no errors
- **DHT**: 56 peers found for a busy swarm with trackers *fully disabled*, and a
  bare trackerless magnet resolved its full 15-file listing via DHT → BEP 9
- **Seeding**: essaim served a torrent to another essaim at 6.2 MB/s uncapped,
  and the global cap held across three rates — 512→518, 1024→1058, 2048→2136 KB/s
- **Daemon**: downloaded to completion while staying responsive, restored a
  finished torrent across a restart in under a second with no network, and
  resumed seeding — served 5.48 MB at 726 KB/s against its own 700 cap
- `machin build --race-safe` passes: engine, seeder **and daemon** are all
  **proved** data-race free

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

## Running in the background

`get` and `seed` block, which is fine for something that finishes in a minute and
useless for anything that doesn't — an agent can't hold a call for hours. So
there is a daemon:

```sh
essaim daemon start                                  # loopback, idempotent
essaim add "magnet:?xt=urn:btih:…" --dir ./dl --seed # returns an id immediately
essaim status                                        # poll; JSON, one row per torrent
essaim set <id> --no-seed --up-limit 512             # adjust a torrent in place
essaim rm <id>
essaim daemon stop
```

`set` exists because the control plane could create and destroy a torrent but
not change one: `seed`, `up_limit` and `down_limit` were fixed at `add` time, so
altering a single integer meant `rm` + `add`, which threw away the record and
re-resolved the metadata. It patches only the fields you pass, so `set --seed` never
silently resets an upload cap.

### Capping the download

```sh
essaim get "magnet:…" --dir ./dl --down-limit 512     # KB/s, global across peers
essaim add "magnet:…" --dir ./dl --down-limit 512
essaim set <id> --down-limit 512
```

It paces how fast blocks are **drained from the socket**, not how fast they are
requested. Requests stay pipelined — a piece still costs one round trip — and
TCP's window does the actual limiting. Pacing the requests instead would
serialise the pipeline and still not stop a fast peer from filling the buffer.

Measured against a live swarm, 45 s each, uncapped ≈ 1040 KB/s:

| cap | completed-piece throughput |
|---|---|
| 512 KB/s | 353 KB/s |
| 128 KB/s | 85 KB/s |

Both are under their cap and the ratio between them is 4.15 against the 4.0
asked for. The figures sit *below* the cap because `bytes` counts only
**completed** pieces, and with dozens of peers there is always data in flight
that has not finished a piece yet.

Unlike the other three, a change to `--down-limit` applies **the next time the
torrent starts**, not immediately: the pacer takes its interval when the job
starts, and restarting a running job from the control loop would mean sending
on an unbuffered channel to workers that may be parked — which hangs the
supervisor. That was tried, and it froze the whole daemon.

### Stopping at a ratio

`--up-limit` bounds the **rate** and never ends. A ratio is the thing that
ends it:

```sh
essaim add "magnet:…" --dir ./dl --seed --ratio-pct 150   # stop after uploading 1.5x
essaim set <id> --ratio-pct 50                            # or change your mind later
```

It is expressed in **percent of what you downloaded** — `50` is 0.5x, `200` is
2x, `0` never stops — because there are no floats here and percent is what the
number means to a person.

The ratio is checked in two places, after every pump *and* before starting a
seeder, because a limit that only stopped a running seeder would be undone by
the next loop restarting it. Your `seed` flag stays your intent; the ratio is
what decides whether it is acted on, so "I asked to seed" and "it has finished
seeding" remain two different facts.

It is **single-actor**: one loop owns the job table and handles each request
inline, so there is no lock and no second writer. That isn't caution for its own
sake — the download engine already runs a goroutine per peer, and an HTTP handler
touching the same state would make `machin build --race-safe` refuse to build.
A control-plane request takes microseconds against a download that takes minutes.

A freshly added torrent sits in `resolving`, then at 0 pieces, for up to ~30 s
while it announces to trackers and runs a DHT lookup. That is discovery, not a
stall — which is exactly why this belongs in a daemon rather than a call an agent
has to hold open.

State lives in `~/.essaim/` (override with `ESSAIM_HOME`): a small registry of
*which* torrents you asked for, plus a `.torrent` cache. Per-torrent progress is
still re-derived from the files on disk, so a restart re-verifies rather than
trusting a journal — a completed torrent comes back **instantly, with no network
at all**.

### Surviving a reboot

```sh
mkdir -p ~/.config/systemd/user
essaim daemon unit > ~/.config/systemd/user/essaim.service
systemctl --user daemon-reload && systemctl --user enable --now essaim
loginctl enable-linger $USER      # keeps it running after you log out
```

`essaim daemon unit` **prints** a unit rather than installing one. Registering a
service is privileged and host-shaped, and cli-daemon-spec deliberately leaves
boot persistence out of scope, so essaim hands you a file to read first. No sudo
needed for the user-unit path.

**The control API binds to loopback by default.** Reaching further needs both
`--host` and `--token`, because that API accepts magnets. The peer port (6881) is
the only thing meant to face the internet.

## Seeding

**Off by default.** essaim opens no listening port and uploads nothing unless you
ask:

```sh
essaim seed ./file.torrent --dir ./dl --up-limit 500    # share what you have
essaim get  ./file.torrent --dir ./dl --seed            # download, then keep seeding
```

`--up-limit` is a **global** cap in KB/s — a token bucket shared by every
connection, not a per-peer limit. A burst of up to 4 blocks is allowed, so a very
short transfer can measure a few percent over the cap; over any real duration it
converges.

### Capping the download too

`--down-limit` is the mirror image, in the same units and with the same global
shape:

```sh
essaim get ./file.torrent --dir ./dl --down-limit 500   # leave the link usable
essaim add "magnet:…" --dir ./dl --down-limit 500       # same, under the daemon
essaim set <id> --down-limit 0                          # 0 means uncapped
```

It paces how fast blocks are **drained from the socket**, not how fast they are
requested. Requests stay pipelined, so a piece still costs one round trip, and
TCP's own backpressure does the limiting. Pacing the requests instead would
serialise the pipeline — slower for the same cap, and still no bound on a fast
peer filling the receive buffer.

One caveat: changing `--down-limit` on a **running** torrent restarts peer
discovery, because a job's pacer is created with its interval when the job
starts. Setting it at `add` time costs nothing.

Two machines, no tracker and no DHT:

```sh
# on the sender
essaim seed ./f.torrent --dir ./dl --port 51413 --no-announce
# on the receiver
essaim get  ./f.torrent --dir ./in --peer 10.0.0.2:51413 --no-dht
```

## Agent-first conventions

Follows the [cli-specs](https://cli-specs.intrane.fr/) family:

| spec | status |
|---|---|
| cli-output-spec | stdout=data, stderr=context, semantic exit codes, typed errors, `help-json` |
| cli-guide-spec | `essaim guide` — model, loop, concepts, gotchas, embedded in the binary |
| cli-update-spec | `essaim update` (content-hash + smoke test + `.bak`), `install`/`uninstall` |
| cli-feedback-spec | `essaim feedback "…" --kind bug` — dual-write with an idempotency key |
| cli-telemetry-spec | **deliberately not adopted** (see below) |
| cli-daemon-spec | `serve` + `/_health` + token-gated `/_shutdown` + `daemon start\|stop\|status`, loopback by default |

Success is `{"ok":true,"version":"…","data":{…}}` and failure is
`{"ok":false,"version":"…","error":{…}}` with a matching exit code. As of 0.5.0 the
daemon-backed commands (`add`, `status`, `set`, `rm`) obey this too — before that
they printed the daemon's raw HTTP reply, so their payload sat at the top level
instead of under `.data`. Parsing no longer depends on which commands happen to be
daemon-backed.

Two deliberate exceptions: `guide` puts its payload under `.guide` (that shape is
cli-guide-spec's, not ours), and a `get` that ends incomplete exits 105 with
**both** an `error` and a `data` block, because partial progress is still worth
reporting.

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
./tests/run.sh  # 325 assertions across 11 module suites + a CLI suite
```

Tests need no network: the tracker suite stands up a fake BEP 15 tracker, the
engine suite stands up a real seeder speaking the actual peer protocol, and the
index suite parses recorded response fixtures.

## Limits

- No `watch` (folder monitoring) yet.
- The daemon is single-actor, so a very large job table would serialise
  control-plane requests behind each other. Fine for tens of torrents.
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
