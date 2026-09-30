#!/bin/sh
# shellcheck shell=dash
# A cached list is damaged (e.g. power loss while writing) and GitHub is unreachable.
# Expected: the damaged list is replaced with an empty one and sing-box starts.

set -eu

. "$(dirname "$0")/../lib.sh"

block_github() {
    on_router sh -c "uci add_list dhcp.@dnsmasq[0].address='/github.com/0.0.0.0' && uci commit dhcp && /etc/init.d/dnsmasq reload"
}

unblock_github() {
    on_router sh -c "uci del_list dhcp.@dnsmasq[0].address='/github.com/0.0.0.0' && uci commit dhcp && /etc/init.d/dnsmasq reload"
}

cleanup() {
    unblock_github > /dev/null 2>&1 || true
    dc start proxy > /dev/null
}
trap cleanup EXIT

result=0

dc start proxy > /dev/null
load_fixture proxy

info "Damaging a cached list, blocking GitHub and stopping the proxy"
on_router sh -c 'head -c 100 /dev/urandom > /etc/okop/rulesets/main-youtube-community-ruleset.srs'
block_github
dc stop proxy > /dev/null
reboot_router

if singbox_stable; then
    pass "sing-box is running with a damaged cached list"
else
    fail "sing-box is not running or restarts in a loop" || result=1
fi

if wait_for 15 client_resolves; then
    pass "client DNS works"
else
    fail "client DNS is broken" || result=1
fi

exit "$result"
