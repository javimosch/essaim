# essaim

An agent-first BitTorrent client. One static binary, no runtime, JSON on stdout.

Written in [MFL](https://github.com/javimosch/machin) — bencode, the peer wire
protocol, trackers and SHA-1 verification are all pure MFL. No libtorrent, no
Node, no Python.

```sh
essaim info ./file.torrent          # read metadata, download nothing
essaim get  ./file.torrent --dir ./dl
essaim guide                        # the whole mental model, embedded
essaim help-json                    # machine-readable command catalog
```

Progress goes to stderr, the result to stdout, so `essaim get … | jq` works while
you still watch it run. Exit codes are semantic: `0` complete, `105` incomplete
(rerun to resume), `100` no peers, `82` bad input.

## What it does

- **Trackers** over UDP (BEP 15) and HTTP (BEP 3)
- **Peer wire protocol** (BEP 3) with pipelined 16 KiB blocks
- **Verification**: nothing is believed until a piece's SHA-1 matches the
  torrent's commitment
- **Resume**: there is no progress journal — the files on disk *are* the state,
  so a rerun re-verifies and continues

## Status

Live-verified: a 5.48 MB, 13-file, multi-file torrent pulled from a real swarm
in 3.3 s, every piece independently re-checked against the `.torrent`.

Magnet links parse (`info`) but do not download yet — they carry no piece
hashes, and fetching metadata from peers (BEP 9) is not implemented.

## Build

```sh
./build.sh      # machin encode src/*.src > essaim.mfl && machin build essaim.mfl
./tests/run.sh  # every suite
```
