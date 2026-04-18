# networkd-try

Safely try risky changes under `/etc/systemd/network/` on a remote box
(e.g. flipping the default route into a WireGuard tunnel), with a
**wall-clock-anchored, reboot-based auto-rollback** so a bad config
can't brick SSH access.

Designed with the "remote CGNAT'd box I can barely reach" scenario
in mind, but the tool is generic — it knows nothing about WireGuard.

## How it works

```
┌────────────────────────────────────────────────────────────────────┐
│ 1. begin    snapshot /etc/systemd/network → /var/lib/networkd-try/ │
│ 2. (edit)   sudoedit /etc/systemd/network/*  as much as you like   │
│ 3. apply    arm a systemd timer with OnCalendar=<now+10m>, reboot  │
│    │                                                               │
│    ├─ you reconnect within 10 min → `ok`  → disarm, keep change    │
│    └─ you don't                    → timer fires                   │
│                                      → service restores snapshot   │
│                                      → service reboots             │
│                                      → box comes back with old cfg │
└────────────────────────────────────────────────────────────────────┘
```

Key properties:

- **Absolute wall-clock deadline** (`OnCalendar=2026-04-18 10:00:00 UTC`),
  not "N minutes after boot". If the box takes 8 min to come up, you
  still only have 2 min — no accidental extension.
- **`Persistent=true`** on the timer: if the machine is wedged past the
  deadline (kernel panic loop, long fsck, etc.), the rollback fires on
  the next successful boot instead of silently missing.
- **`ConditionPathExists=/var/lib/networkd-try/pending`** on the service:
  if you've already committed via `ok`, a late-firing timer becomes a
  harmless no-op.
- **Snapshot with `rsync --delete`**: added, removed and modified files
  are all restored correctly.

## Install (on the target box)

```
scp -r networkd-try/ target:/tmp/
ssh target 'sudo /tmp/networkd-try/install.sh'
```

Installs:

| Path                                              | What                            |
|---------------------------------------------------|---------------------------------|
| `/usr/local/sbin/networkd-try`                    | the CLI                         |
| `/etc/systemd/system/networkd-try-rollback.service` | rollback executor             |
| `/etc/systemd/system/networkd-try-rollback.timer` | deadline timer (disabled)       |
| `/etc/networkd-try/preflight.d/`                  | hooks run before `apply` reboots |
| `/var/lib/networkd-try/`                          | state (backup, markers)         |

Nothing is enabled until you run `apply`.

## Usage

```bash
# 1. snapshot
sudo networkd-try begin

# 2. make your changes
sudoedit /etc/systemd/network/wg0.network
#   add / tweak routes, rules, etc.

# 3. try it — reboots immediately, auto-rollback armed for 10 min
sudo networkd-try apply           # 10m default
sudo networkd-try apply -t 5m     # short window
sudo networkd-try apply -t 30m    # long window
sudo networkd-try apply -n        # dry-run: print plan, don't reboot

# 4a. it worked → commit
sudo networkd-try ok

# 4b. it didn't work, you can still SSH → manual rollback + reboot
sudo networkd-try rollback

# 4c. you can't SSH at all → wait; the timer will fire and reboot you
#     back to the old config by itself. No action needed.
```

Helpers:

```bash
sudo networkd-try status    # shows pending state, deadline, timer, diff
sudo networkd-try abort     # discard a `begin` snapshot (only BEFORE apply)
```

## Preflight hooks

Any executable `*.sh` under `/etc/networkd-try/preflight.d/` is run
before `apply` reboots; any non-zero exit aborts. Ship-in-the-box
example: `01-tailscale-online.sh` refuses to reboot if tailscale isn't
`Running` (so you don't lose your backup access path on the very
reboot that's supposed to be recoverable).

Add your own, e.g. to require autossh:

```bash
sudo install -m0755 /dev/stdin /etc/networkd-try/preflight.d/02-autossh.sh <<'EOF'
#!/usr/bin/env bash
systemctl is-active --quiet autossh-vps.service
EOF
```

## Example: flipping default route into a WireGuard tunnel

```bash
sudo networkd-try begin

# edit /etc/systemd/network/wg0.network to e.g.:
#   [Route]
#   Destination=0.0.0.0/0
#   Gateway=10.0.0.1
#   GatewayOnLink=yes
#   Metric=50
#
# (and drop any dead Table=100 / From=10.0.0.2 policy-routing bits)

sudo networkd-try apply -t 10m
# … reboot, reconnect via SSH (LAN / tailscale / reverse-ssh / …) …
curl -I https://www.google.com    # now goes through wg by default
sudo networkd-try ok
```

## Caveats

- Only files under `/etc/systemd/network/` are snapshotted. If your
  change also touches `/etc/nftables*`, `/etc/netplan/`, `/etc/wireguard/`,
  etc., those are **not** covered — extend by hand or pair with a
  filesystem snapshot (btrfs/zfs/LVM).
- If the kernel itself won't boot, no userspace timer can save you.
  Keep a separate serial/IPMI/physical-access recovery path.
- `networkd-try rollback` reboots the machine. `ok` does not.
