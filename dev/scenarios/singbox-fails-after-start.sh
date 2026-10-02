#!/bin/sh
# shellcheck shell=dash
# A config that passes "sing-box check" but fails when sing-box runs: the mixed proxy port is the
# Clash API port (both listen on the LAN address). check does not bind ports, so the start used to
# succeed while sing-box crash-looped behind the installed interception.
# Expected: okop notices that sing-box did not come up and rolls back: no nft table, dnsmasq given
# back, client DNS works.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

result=0

load_fixture proxy
info "Starting with the mixed proxy on the Clash API port"
on_router sh -c "
    uci set okop.main.mixed_proxy_enabled=1
    uci set okop.main.mixed_proxy_port=9090
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 45

if on_router sh -c 'logread -e sing-box | grep -q "address already in use"'; then
    pass "baseline: sing-box failed to bind the port"
else
    fail "baseline: sing-box did not fail, the scenario does not test anything" || result=1
fi

if on_router nft list table inet OkopTable > /dev/null 2>&1; then
    fail "the nft table is left behind sing-box that is not running" || result=1
else
    pass "the nft table is removed"
fi

if dnsmasq_uses_singbox; then
    fail "dnsmasq still forwards to sing-box that is not running" || result=1
else
    pass "dnsmasq does not forward to sing-box"
fi

if wait_for 15 client_resolves; then
    pass "client DNS works"
else
    fail "client has no DNS" || result=1
fi

exit "$result"
