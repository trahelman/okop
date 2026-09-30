#!/bin/sh
# shellcheck shell=dash
# Router boots while the outbound used to download rule sets is unavailable.
# Rule set cache in /tmp is gone after reboot, so sing-box cannot fetch the lists.
# Expected: sing-box starts anyway and LAN clients keep working DNS.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    dc start proxy > /dev/null
}
trap cleanup EXIT

result=0

dc start proxy > /dev/null
load_fixture proxy
wait_for 15 client_resolves || fail "baseline: client DNS does not work with the proxy up"

info "Stopping the proxy"
dc stop proxy > /dev/null
reboot_router

if wait_for 15 client_resolves; then
    pass "client DNS works after boot with the outbound down"
else
    fail "client DNS is broken after boot with the outbound down" || result=1
fi

if singbox_stable; then
    pass "sing-box is running"
else
    fail "sing-box is not running or restarts in a loop" || result=1
fi

exit "$result"
