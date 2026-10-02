#!/bin/sh
# shellcheck shell=dash
# dnsmasq forwards to sing-box only while okop runs. Two ways to leave it pointing at a sing-box that
# is gone, both reachable from LuCI with one click:
#   - "Не трогать мой DHCP!" (dont_touch_dhcp) is enabled while okop is already running;
#   - the "Disable" button in Diagnostics, followed by a reboot.
# Expected in both cases: the user's DNS settings come back and the LAN keeps resolving.

set -eu

. "$(dirname "$0")/../lib.sh"

show_state() {
    on_router sh -c 'uci show dhcp.@dnsmasq[0] | grep -E "server|noresolv"; logread -e okop | grep -E "dnsmasq|guard" | tail -5'
}

cleanup() {
    on_router /etc/init.d/okop enable > /dev/null 2>&1 || true
    on_router sh -c 'uci -q set okop.settings.dont_touch_dhcp=0; uci commit okop' || true
}

trap cleanup EXIT

result=0

# dont_touch_dhcp enabled while okop runs
load_fixture proxy
wait_for 30 client_gets_fakeip || { show_state; fail "baseline: client DNS does not go through sing-box"; }

info "Enabling dont_touch_dhcp while okop runs, then stopping okop"
on_router sh -c 'uci set okop.settings.dont_touch_dhcp=1; uci commit okop'
on_router /etc/init.d/okop restart > /dev/null 2>&1
wait_okop
on_router /etc/init.d/okop stop > /dev/null 2>&1

if dnsmasq_uses_singbox; then
    fail "dnsmasq still forwards to sing-box after a stop with dont_touch_dhcp enabled" || result=1
    show_state
else
    pass "dnsmasq is restored on stop even with dont_touch_dhcp enabled"
fi

if wait_for 15 client_resolves; then
    pass "client DNS works after a stop with dont_touch_dhcp enabled"
else
    fail "client has no DNS after a stop with dont_touch_dhcp enabled" || result=1
    show_state
fi

# okop disabled, then rebooted: okop does not run, and it disabled sing-box's autostart too
load_fixture proxy
wait_for 30 client_gets_fakeip || { show_state; fail "baseline: client DNS does not go through sing-box"; }

info "Disabling okop and rebooting the router"
on_router /etc/init.d/okop disable > /dev/null 2>&1
reboot_router

if on_router pidof sing-box > /dev/null; then
    fail "baseline: sing-box is running although okop is disabled" || result=1
elif dnsmasq_uses_singbox; then
    fail "dnsmasq still forwards to sing-box after okop was disabled and the router rebooted" || result=1
    show_state
else
    pass "dnsmasq is restored when okop is disabled"
fi

if wait_for 15 client_resolves; then
    pass "client DNS works after okop was disabled and the router rebooted"
else
    fail "client has no DNS after okop was disabled and the router rebooted" || result=1
    show_state
fi

exit "$result"
