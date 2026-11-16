#!/bin/sh
# GitHub may return either compact or indented JSON; installation must find assets in both.
# Extract only the parser: never source or run the installer, which changes installed packages.
set -eu
. "$(dirname "$0")/../lib.sh"

info "Checking installer release assets without installing packages"
{
    sed -n '/^release_assets() {$/,/^}$/p' "$DEV_DIR/../install.sh"
    cat <<'SH'
set -eu
compact='{"assets":[{"url":"https://api.github.com/repos/trahelman/okop/releases/assets/1","name":"okop-0.10.ipk"},{"url":"https://api.github.com/repos/trahelman/okop/releases/assets/2","name":"luci-app-okop-0.10.ipk"},{"url":"https://api.github.com/repos/trahelman/okop/releases/assets/3","name":"okop-0.10.apk"}],"tarball_url":"https://api.github.com/repos/trahelman/okop/tarball/0.10"}'
pretty='{
  "assets": [
    {
      "url": "https://api.github.com/repos/trahelman/okop/releases/assets/1",
      "name": "okop-0.10.ipk"
    },
    {
      "url": "https://api.github.com/repos/trahelman/okop/releases/assets/2",
      "name": "luci-app-okop-0.10.ipk"
    },
    {
      "url": "https://api.github.com/repos/trahelman/okop/releases/assets/3",
      "name": "okop-0.10.apk"
    }
  ],
  "tarball_url": "https://api.github.com/repos/trahelman/okop/tarball/0.10"
}'
expected_ipk='https://api.github.com/repos/trahelman/okop/releases/assets/1 okop-0.10.ipk
https://api.github.com/repos/trahelman/okop/releases/assets/2 luci-app-okop-0.10.ipk'
expected_apk='https://api.github.com/repos/trahelman/okop/releases/assets/3 okop-0.10.apk'
for format in compact pretty; do
    case "$format" in compact) json="$compact" ;; pretty) json="$pretty" ;; esac
    for ext in ipk apk; do
        case "$ext" in ipk) expected="$expected_ipk" ;; apk) expected="$expected_apk" ;; esac
        actual="$(printf '%s\n' "$json" | release_assets "$ext")"
        if [ "$actual" != "$expected" ]; then
            echo "FAIL: installer finds $ext assets in $format GitHub JSON"
            exit 1
        fi
        echo "PASS: installer finds $ext assets in $format GitHub JSON"
    done
    [ -z "$(printf '%s\n' "$json" | release_assets zip)" ] || {
        echo "FAIL: installer ignores source archives and unmatched extensions"
        exit 1
    }
done
echo "PASS: installer ignores source archives and unmatched extensions"
SH
} | on_router sh
