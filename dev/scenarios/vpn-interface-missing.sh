#!/bin/sh
# shellcheck shell=dash
# Rule sets are downloaded through a VPN section whose interface does not exist.
# Expected: sing-box starts anyway and LAN clients keep working DNS.

set -eu

. "$(dirname "$0")/../lib.sh"

result=0

load_fixture vpn-missing
reboot_router

if wait_for 15 client_resolves; then
    pass "client DNS works with the VPN interface missing"
else
    fail "client DNS is broken with the VPN interface missing" || result=1
fi

if singbox_stable; then
    pass "sing-box is running"
else
    fail "sing-box is not running or restarts in a loop" || result=1
fi

exit "$result"
