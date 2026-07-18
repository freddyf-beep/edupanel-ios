#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "Usage: ./scripts/serve-sim.sh <simulator-udid>"
  echo "Find a UDID with: xcrun simctl list devices available"
  exit 1
fi

SIM="$1"

cleanup_serve_sim() {
  npx --yes serve-sim@0.1.43 --kill "$SIM" >/dev/null 2>&1 || true
}

trap cleanup_serve_sim EXIT INT TERM HUP
cleanup_serve_sim
npx --yes serve-sim@0.1.43 "$SIM"
