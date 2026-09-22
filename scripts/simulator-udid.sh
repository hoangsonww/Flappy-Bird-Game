#!/usr/bin/env bash
#
# Print the UDID of an iOS Simulator to build against.
#
#   scripts/simulator-udid.sh
#   SIMULATOR="iPhone 16 Pro" scripts/simulator-udid.sh
#
# Resolving a UDID rather than passing `name=…` to xcodebuild matters: a bare
# name makes xcodebuild default to `OS:latest`, so a device that only exists on
# an older runtime stops matching the moment a newer runtime is installed —
# which looks exactly like a broken project. The UDID is unambiguous.
set -euo pipefail

SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"

devices="$(xcrun simctl list devices available)"

# Exact name first, then any iPhone — the last one listed, which is the newest
# runtime simctl knows about.
udid="$(grep -F "$SIMULATOR (" <<<"$devices" | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"

if [ -z "$udid" ]; then
  udid="$(grep -E '^[[:space:]]+iPhone ' <<<"$devices" | tail -1 \
          | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
fi

if [ -z "$udid" ]; then
  echo "No available iOS Simulator found. Open Xcode ▸ Settings ▸ Components" >&2
  echo "and install a simulator runtime, or run: xcrun simctl list devices" >&2
  exit 1
fi

printf '%s\n' "$udid"
