#!/bin/sh
# shellcheck shell=dash
# First boot without downloaded lists while GitHub is unreachable both through the proxy and directly.
# Expected: sing-box starts with empty rule sets, and picks up the lists without a restart once they are downloaded.

set -eu

. "$(dirname "$0")/../lib.sh"

# dnsmasq answers github.com with 0.0.0.0, this survives reboots (/etc/hosts is managed by Docker)
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

info "Removing downloaded lists, blocking GitHub and stopping the proxy"
on_router sh -c 'rm -f /etc/okop/rulesets/*'
block_github
dc stop proxy > /dev/null
reboot_router

if wait_for 15 client_resolves; then
    pass "client DNS works without downloaded lists"
else
    fail "client DNS is broken without downloaded lists" || result=1
fi

if singbox_stable; then
    pass "sing-box is running with empty rule sets"
else
    fail "sing-box is not running or restarts in a loop" || result=1
fi

if singbox_answers_fakeip; then
    pass "sing-box answers the fakeip service domain with empty rule sets"
else
    fail "sing-box does not answer the fakeip service domain with empty rule sets" || result=1
fi

info "Unblocking GitHub, starting the proxy and updating the lists"
unblock_github
dc start proxy > /dev/null
pid_before="$(on_router pidof sing-box || true)"
on_router okop list_update > /dev/null 2>&1 || true

if wait_for 30 client_gets_fakeip; then
    pass "downloaded lists are applied"
else
    fail "downloaded lists are not applied" || result=1
fi

if [ -n "$pid_before" ] && [ "$(on_router pidof sing-box || true)" = "$pid_before" ]; then
    pass "sing-box picked up the lists without a restart"
else
    fail "sing-box was restarted or is not running" || result=1
fi

exit "$result"
