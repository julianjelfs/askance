#!/bin/sh
# Writes a hash of the web build into its service worker, so every deploy
# that changes anything installs a new worker with a fresh cache, and a
# rebuild that changes nothing leaves installed copies alone.
#
#   tool/stamp-sw.sh build/web
set -eu
dir=${1:?usage: stamp-sw.sh <web build dir>}
hash=$(cd "$dir" && find . -type f ! -path './.git/*' ! -name sw.js | LC_ALL=C sort |
	xargs shasum | shasum | cut -c1-12)
sed -i.bak "s/^const BUILD = '[^']*';/const BUILD = '$hash';/" "$dir/sw.js"
rm "$dir/sw.js.bak"
grep -q "const BUILD = '$hash';" "$dir/sw.js" || { echo "stamp-sw: BUILD line not found in $dir/sw.js" >&2; exit 1; }
echo "sw.js stamped $hash"
