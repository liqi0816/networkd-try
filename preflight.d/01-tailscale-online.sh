#!/usr/bin/env bash
# networkd-try preflight: refuse to reboot if tailscale is not Online.
#
# Rationale: tailscale is a primary out-of-band recovery path. If it's
# already broken BEFORE we flip the config, the rollback window may not
# be enough to save us. Better to abort early and investigate.
#
# Skip gracefully if tailscale is not installed on this host.
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale not installed — skipping check"
  exit 0
fi

status=$(tailscale status --json 2>/dev/null || true)
if [[ -z "$status" ]]; then
  echo "tailscale status returned nothing (daemon down?)"
  exit 1
fi

# BackendState is "Running" when the node is up and logged in; other
# values (Stopped, NeedsLogin, NoState, …) mean we should not reboot.
backend=$(printf '%s' "$status" | grep -oE '"BackendState":[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)
case "$backend" in
  Running) echo "tailscale BackendState=Running — OK" ;;
  "")      echo "could not parse tailscale BackendState"; exit 1 ;;
  *)       echo "tailscale BackendState=$backend (expected Running)"; exit 1 ;;
esac
