#!/usr/bin/env bash
#
# install.sh — place networkd-try on the target box.
#
# Idempotent. Does NOT enable the timer (that happens per-apply).
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "must be run as root" >&2; exit 2; }

# Binary
install -m0755 "$SRC/networkd-try" /usr/local/sbin/networkd-try

# Units
install -m0644 "$SRC/systemd/networkd-try-rollback.service" /etc/systemd/system/
install -m0644 "$SRC/systemd/networkd-try-rollback.timer"   /etc/systemd/system/

# Preflight hook directory + examples
install -d -m0755 /etc/networkd-try/preflight.d
if [[ -d "$SRC/preflight.d" ]]; then
  for f in "$SRC/preflight.d/"*.sh; do
    [[ -e "$f" ]] || continue
    install -m0755 "$f" /etc/networkd-try/preflight.d/
  done
fi

# State dir
install -d -m0700 /var/lib/networkd-try

systemctl daemon-reload

echo "Installed:"
echo "  /usr/local/sbin/networkd-try"
echo "  /etc/systemd/system/networkd-try-rollback.{service,timer}"
echo "  /etc/networkd-try/preflight.d/  (example hooks, all optional)"
echo "  /var/lib/networkd-try/          (state)"
echo
echo "Usage:  networkd-try --help"
