# #0-313 measurement 2 and #0-285's measurements on the build VM (2026-11-23)

Run by the owner on `factory-build` (Lima, aarch64, 12 GiB), right after the VM was made anew from `main` `a937d62c`,
while no dispatcher run was live. Each script ran as root through `limactl shell factory-build sudo bash -s < <script>`
and removed what it made (listeners, a dummy interface, a temporary egress rule, a temporary user `factory-t` with its
own rootless daemon, the image tarball). The `.txt` files are the scripts' `RESULT` lines; Lima's "Session terminated" lines,
printed when a script ended `factory-t`'s session, are left out. After the runs, the scripts gained
`# shellcheck disable=SC2016` lines and two fixes of shellcheck findings (`${T:?}`, an unused variable), so that
`check-shell.rb` passes; what they run is unchanged.

| Script | What it measures | Log |
|---|---|---|
| `measure-0285-0313.sh` | B: a slot's wipe and its images' reload, three times; a pull from the network; whether `user@<uid>` comes back by itself under linger. Its part A and its port test failed: the helper image is pulled by digest, so `buildpack-deps:<tag>` was `<none>` ("invalid reference format") | `measure-0285-0313.txt` |
| `measure-a-0313.sh` | A again, with the helper by ID: which address a container of `factory`'s daemon reaches a listener of `dispatcher` at; a port another slot published on a fixed port | `measure-a-0313.txt` |
| `measure-c-0313.sh` | a unix socket of group `factory`; another slot's port published at random (`-P`, as Testcontainers does) | `measure-c-0313.txt` |
| `measure-d-0285.sh` | #0-285's option C: a slot's daemon publishing on an address of its own (`daemon.json` `ip` and `host-gateway-ip`), one rule per slot | `measure-d-0285.txt` |

## Results

- **`dispatcher` reaching Anthropic (#0-313's measurement 2 as first written):** `curl` as `dispatcher` to
  `https://api.anthropic.com/v1/messages` answered HTTP 405 (a GET on a POST route): the VM's filter lets
  `dispatcher`'s uid reach the API, through FACTORY-EGRESS's allow-list. AC7's split by uid keeps it so for
  `dispatcher` and closes it to the slots' uids.
- **The rootless network:** `rootlesskit --net=slirp4netns --disable-host-loopback --port-driver=builtin`;
  `host.docker.internal` is the VM's address (`192.168.5.15`, `provision.sh`'s `host-gateway-ip`); the ephemeral range
  is 32768–60999.
- **A container of `factory` reaching a listener of `dispatcher` (#0-313 AC5):**

  | Address | Today's chain | With one `ACCEPT` for it |
  |---|---|---|
  | `10.0.2.2` (the host's loopback through slirp) | refused | — |
  | the VM's address, port 18080 | refused | — |
  | **the VM's address, a port of the ephemeral range (33768)** | **reached** | — |
  | **a dummy address `10.203.0.1`, port 18080** | refused | **reached** |

  The VM's address is reached on the ephemeral range only by FACTORY-EGRESS's rule for rootlesskit's published ports
  (`-o lo -d <vm_ip> --dport 32768:60999 -j ACCEPT`, for Testcontainers), not by a rule of the proxy's.
- **A unix socket under `/run`:** not reached, as group `dispatcher` or `factory` alike. The likely cause is
  rootlesskit's `--copy-up=/run`: the daemon sees a copy of `/run` made when it started, not a later directory, so a
  socket for a task's container lives outside `/run`. Not measured further: #0-313 uses TCP.
- **Another slot's published port (#0-285 AC4):** on a fixed port outside the ephemeral range (15432), refused from
  every address; **published at random (`-P`, port 32768), reached from `factory`'s container through the VM's address
  and `host.docker.internal`**. With two slots on today's chain, a task reaches the other slot's Testcontainers
  (PostgreSQL, Kafka).
- **Option C (`measure-d-0285`):** a slot's daemon with `daemon.json` `"ip": "10.204.2.1"` and `"host-gateway-ip":
  "10.204.2.1"`, and one rule (its uid, `-o lo -d 10.204.2.1 -j ACCEPT`): a `-P` port is published and listens on
  `10.204.2.1` only; its own slot reaches it through `host.docker.internal` and `10.204.2.1`; the other slot does not,
  through `10.204.2.1`, the VM's address or `host.docker.internal`.
- **A slot's wipe (B):**

  | Run | Stop | Remove | Home anew, daemon up | `docker load` (332 MB) | Total |
  |---|---|---|---|---|---|
  | 1 | 1.2 s | 5.0 s | 0.8 s | 7.7 s | 14.7 s |
  | 2 | 1.2 s | 0.2 s | 1.7 s | 10.0 s | 13.1 s |
  | 3 | 1.2 s | 0.1 s | 1.7 s | 8.8 s | 11.9 s |

  The tarball held `postgres:16-alpine`, `apache/kafka:3.9.2` and `alpine:latest`: the VM, made anew, had no task image
  yet. A task image of 2–3 GB would load in about 1–1.5 minutes at the rate measured (an estimate, not measured). A
  pull of PostgreSQL and Kafka from the network took 12.0 s.
- **Linger:** after `loginctl terminate-user` and a stop of `user@<uid>.service`, the manager was not active again 5 s
  later. The wipe still keeps it down explicitly (#0-285): 5 s rules nothing out.

## What it decides

- **#0-313:** the proxy listens on an address of its own on a dummy interface (`FACTORY_PROXY_ADDR`, for example
  `10.203.0.1`), which `provision.sh` makes, with one FACTORY-EGRESS `ACCEPT` for that address and port. Not on the
  VM's address: reaching it would rest on the rule for rootlesskit's ports, and in a cloud the VM's address is on a
  network outside the VM (AC5).
- **#0-285:** option C. Each slot's daemon publishes on an address of its own (`daemon.json` `ip` and
  `host-gateway-ip`), each slot's uid may reach only its own address, and the ephemeral-range rule on the VM's address
  goes. The wipe's time (about 15 s, about 1–1.5 minutes with a task image) is well under the 3 minutes set as the
  limit, so no registry mirror is needed. A real Testcontainers suite (Ryuk included) in two slots at once is the
  trial's (#0-285 AC4).
