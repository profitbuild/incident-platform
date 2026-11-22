# #0-313 measurement 3 (AC9): `ANTHROPIC_UNIX_SOCKET` on the pinned Claude Code, 2026-11-22

The material of one measurement, kept so its results can be read again later. What it found, and what that means, is
the Record of `../../m2.md` ("M2.7 (#0-313), measurement 3"). This directory is evidence for that entry. It is no
decision, and no code runs it.

## Where each result is shown

| Result (`m2.md`) | Files |
|---|---|
| A: the socket alone carries TLS to `api.anthropic.com` | `out/A-bytes/gw.jsonl` (`first` `16030105df010005`, `sni` `api.anthropic.com`); `out/A-socket/stream.jsonl` (8 `api_retry`, no `result`); `out/A-debug/debug-A.txt` ("Connection error.") |
| B: socket + `http://` base URL answers through the socket | `out/B-socket-http/gw.jsonl` (`via` `unix`, `Host: proxy.invalid:8080`, token in both headers); `out/B-socket-http/stream.jsonl` (`apiKeySource` `"apiKeyHelper"`, `result` `ok-m313`) |
| C: a missing socket does not fall back to TCP | `out/C-missing-socket/` (no network at all); `out/C2/stream.jsonl` (6 `api_retry`) and `out/C2/terminal.txt` (the gateway, reachable over TCP, got nothing; its control answered over TCP) |
| D: the socket replaces no credential | `out/D-no-helper/stream.jsonl` (`apiKeySource` `"none"`, "Not logged in") |
| E: `--network none` leaves the socket the only way out | `out/E-control-no-socket/stream.jsonl` (6 `api_retry`, no `result`) |

Each `out/<variant>/` holds what `run.sh` wrote: `stream.jsonl` (the call's `stream-json`), `stderr.txt`,
`exit.txt` (`timeout`'s status: 124 is the limit) and `gw.jsonl` (the gateway's log). `C2/` has no `exit.txt` and
no `gw.jsonl`: see below.

## The files

- `run.sh <variant> <settings dir> [VAR=value ...]`: one variant. It starts the gateway, runs the call (F3's argv,
  as in `m2.md`) in a container on `--network none`, and writes `out/<variant>/`. `LIMIT` sets `timeout`'s seconds
  (default 90). `EXTRA_ARGS` adds flags to `claude` (only `--debug-file` was used, for diagnosis).
- `gw.mjs`: the fake gateway (`node:http`), on a unix socket in a Docker volume, and on TCP 8080 when `TCP` is set.
- `etc-claude-code/managed-settings.json` and `etc-nohelper/managed-settings.json`: the managed file, mounted
  read-only as `/etc/claude-code`, with and without `apiKeyHelper`.

## What differs from what ran

- **`run.sh`:** three changes, none to the call or to what a run writes.
  - Two for CI's shellcheck: `"${LIMIT:-90}"` is now quoted, and a `shellcheck disable=SC2086` with its reason sits
    above the call, whose `${EXTRA_ARGS:-}` is split on purpose.
  - The gateway's mount: `gw.mjs` was in a `gw/` directory when the measurement ran and sits beside `run.sh` here, so
    the script mounts the file (`-v "$S/gw.mjs:/gw/gw.mjs:ro"`) instead of `-v "$S/gw:/gw:ro"` (review round 1).
  - The wait for the gateway: `sleep 2` became a wait of up to 10 s for its `"ready"` line. Without that line the
    script stops with the gateway's log, so a gateway that did not start cannot pass for a variant's result (review
    round 1).
- **`gw.mjs` grew while the measurement ran.** The file here is the last version.
  - `A-socket` and `A-debug` ran without the connection log.
  - `A-conn` ran with the connection log, but without the first bytes.
  - `A-bytes`, `B`, `C`, `D` and `E` ran with the first bytes, the version here without `TCP` set.
  - `C2` ran with `TCP` set.

  Each later version only adds logging; none changes an answer.
- **The `A-debug` run's debug log** was written into the workspace, so it is copied in here.

## C2 and its control

These were run by hand, not by `run.sh`, with both containers on one `docker network create --internal m313net` and
the gateway started with `-e TCP=1`. The call was `run.sh`'s, on `--network m313net`, with
`ANTHROPIC_UNIX_SOCKET=/run/sock/missing.sock ANTHROPIC_BASE_URL=http://m313-gw:8080` and a 30 s limit. Its control
was the same call without the socket variable, its stream piped to `jq` and not kept. Their printed output is
`out/C2/terminal.txt`, copied unchanged.

## To repeat it

From this directory, on a machine with Docker:

1. Build the image: `docker build --build-arg FACTORY_NTFY_SERVER= -t ip-devc-0313:c26c6cf7 <repo>/.devcontainer`,
   at `main` `c26c6cf7` (Claude Code 2.1.328, the pin).
2. Clone `factory` at `5576c992` (`v0.1.4`) into `factory/`.
3. Make the token: `mkdir token workspace && printf 'tok-m313-made-up' > token/token`, and `chmod 777 workspace`
   (the call runs as `dev`).
4. Run the variants:
   - `./run.sh A-socket etc-claude-code ANTHROPIC_UNIX_SOCKET=/run/sock/api.sock`
   - `LIMIT=60 ./run.sh B-socket-http etc-claude-code ANTHROPIC_UNIX_SOCKET=/run/sock/api.sock
     ANTHROPIC_BASE_URL=http://proxy.invalid:8080`
   - `LIMIT=30 ./run.sh C-missing-socket etc-claude-code ANTHROPIC_UNIX_SOCKET=/run/sock/missing.sock
     ANTHROPIC_BASE_URL=http://proxy.invalid:8080`
   - `LIMIT=60 ./run.sh D-no-helper etc-nohelper ANTHROPIC_UNIX_SOCKET=/run/sock/api.sock
     ANTHROPIC_BASE_URL=http://proxy.invalid:8080`
   - `LIMIT=30 ./run.sh E-control-no-socket etc-claude-code ANTHROPIC_BASE_URL=http://proxy.invalid:8080`

A new run writes over `out/`, so run it in a copy. The token is made up. The outputs hold the calls' session ids and
the container's paths, and no credential.
