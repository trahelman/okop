#!/bin/sh
# shellcheck shell=dash
# "okop reload" is not only a CLI command: with badwan interface monitoring it runs on every
# "interface.*.up". Only "start" ever pointed dnsmasq at sing-box, so a reload after a stop brought
# everything else up -- sing-box, nft rules, the list_update pid file -- while dnsmasq kept using the
# upstream servers and nothing from the lists was routed.
# Expected: after a reload the lists are routed again, and the DNS guard is back.

set -eu

. "$(dirname "$0")/../lib.sh"

show_state() {
    on_router sh -c 'uci show dhcp.@dnsmasq[0] | grep -E "server|noresolv"; ls /var/run/okop_* 2>/dev/null; logread -e okop | grep -E "dnsmasq|guard|reload" | tail -5'
}

result=0

load_fixture proxy
wait_for 30 client_gets_fakeip || { show_state; fail "baseline: client DNS does not go through sing-box"; }

info "Stopping okop, then reloading it instead of starting it"
on_router /usr/bin/okop stop > /dev/null 2>&1
dnsmasq_uses_singbox && fail "baseline: dnsmasq still forwards to sing-box after a stop"
on_router /usr/bin/okop reload > /dev/null 2>&1
wait_okop

if wait_for 30 dnsmasq_uses_singbox; then
    pass "dnsmasq forwards to sing-box again after a reload"
else
    fail "dnsmasq does not forward to sing-box after a reload" || result=1
    show_state
fi

if wait_for 30 client_gets_fakeip example.com; then
    pass "a user domain is routed after a reload"
else
    fail "a user domain is not routed after a reload" || result=1
    show_state
fi

if dns_guard_running; then
    pass "the DNS guard runs after a reload"
else
    fail "the DNS guard does not run after a reload" || result=1
    show_state
fi

# A reload while okop is already running must not drop the lists either
info "Reloading okop while it is running"
on_router /usr/bin/okop reload > /dev/null 2>&1
wait_okop

if wait_for 30 client_gets_fakeip example.com; then
    pass "a user domain is still routed after a second reload"
else
    fail "a user domain is not routed after a second reload" || result=1
    show_state
fi

exit "$result"
