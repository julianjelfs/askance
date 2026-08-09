#!/usr/bin/env bash
# Resolve a single device id for a platform, or explain why it can't.
#
#   tool/pick-device.sh ios
#   tool/pick-device.sh android
#
# Prints the id on stdout. Refuses to guess when more than one device of that
# platform is attached — picking "the first iPhone" is how you end up
# deploying to someone else's phone.
set -euo pipefail

platform="${1:?usage: pick-device.sh <android|ios|darwin>}"

json=$(flutter devices --machine 2>/dev/null)

read -r -d '' script <<'PY' || true
import json, sys
platform = sys.argv[1]
try:
    devices = json.loads(sys.stdin.read())
except ValueError:
    devices = []
matches = [
    d for d in devices
    if str(d.get('targetPlatform', '')).startswith(platform)
]
for d in matches:
    print(f"{d['id']}\t{d['name']}")
PY

matches=$(printf '%s' "$json" | python3 -c "$script" "$platform")
count=$(printf '%s' "$matches" | grep -c . || true)

if [ "$count" -eq 0 ]; then
  echo "No $platform device attached. Run 'flutter devices' to see what is." >&2
  exit 1
fi

if [ "$count" -gt 1 ]; then
  {
    echo "More than one $platform device is attached, so I will not guess:"
    echo
    printf '%s\n' "$matches" | sed 's/^/  /'
    echo
    case "$platform" in
      ios)     var=IPHONE ;;
      android) var=ANDROID ;;
      *)       var=DEVICE ;;
    esac
    echo "Pick one:  make <target> $var=<id>"
    echo "or export it:  export $var=<id>"
  } >&2
  exit 1
fi

printf '%s' "$matches" | cut -f1
