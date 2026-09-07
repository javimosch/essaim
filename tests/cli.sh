#!/usr/bin/env bash
# CLI-level tests: they run the BUILT BINARY and assert on stdout.
#
# The module suites all assert at the HTTP layer, which is why the daemon-backed
# commands could pass every test while printing the daemon's raw reply instead of
# the CLI envelope. Anything an agent parses off stdout gets checked here.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=./essaim
[ -x "$BIN" ] || { echo "no ./essaim binary -- run ./build.sh first"; exit 1; }

export ESSAIM_HOME="$(mktemp -d)/cli-test-home"
PORT=18931
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1: $2"; fail=1; }

# every success envelope is {"ok":true,"version":"<v>","data":{...}}
env_ok() { # name, json
    python3 - "$1" "$2" <<'PY'
import sys, json
name, raw = sys.argv[1], sys.argv[2]
try: d = json.loads(raw)
except Exception as e: print("FAIL %s: not JSON (%s)" % (name, e)); sys.exit(1)
for k in ("ok", "version", "data"):
    if k not in d: print("FAIL %s: envelope missing %r -- got %s" % (name, k, sorted(d))); sys.exit(1)
if d["ok"] is not True: print("FAIL %s: ok is not true" % name); sys.exit(1)
print("ok   %s" % name)
PY
}

$BIN daemon start --port $PORT >/dev/null 2>&1
sleep 1

A=$($BIN add ./tests/none-a.torrent --dir /tmp/essaim-cli --down-limit 400 --port $PORT 2>/dev/null)
env_ok "add-envelope" "$A" || fail=1
ID=$(printf '%s' "$A" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["torrent"]["id"])' 2>/dev/null)
[ -n "$ID" ] && ok "add-id-under-data" || bad "add-id-under-data" "no .data.torrent.id"

D=$(printf '%s' "$A" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["torrent"]["down_limit_kbs"])' 2>/dev/null)
[ "$D" = "400" ] && ok "add-carries-down-limit" || bad "add-carries-down-limit" "got '$D', want 400"

env_ok "status-envelope" "$($BIN status --port $PORT 2>/dev/null)" || fail=1
env_ok "set-envelope"    "$($BIN set "$ID" --down-limit 900 --port $PORT 2>/dev/null)" || fail=1

S=$($BIN status "$ID" --port $PORT 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["torrent"]["down_limit_kbs"])' 2>/dev/null)
[ "$S" = "900" ] && ok "set-persists-down-limit" || bad "set-persists-down-limit" "got '$S', want 900"

env_ok "rm-envelope" "$($BIN rm "$ID" --port $PORT 2>/dev/null)" || fail=1

# errors are enveloped too, and must NOT exit 0
E=$($BIN rm nosuchid --port $PORT 2>/dev/null); EC=$?
[ "$EC" = "92" ] && ok "rm-unknown-exit-92" || bad "rm-unknown-exit-92" "exit $EC"
printf '%s' "$E" | grep -q '"ok":false' && ok "rm-unknown-envelope" || bad "rm-unknown-envelope" "$E"

$BIN daemon stop --port $PORT >/dev/null 2>&1
rm -rf "$ESSAIM_HOME"
[ "$fail" = 0 ] || { echo; echo "CLI TESTS FAILED"; exit 1; }
echo; echo "CLI TESTS PASSED"
