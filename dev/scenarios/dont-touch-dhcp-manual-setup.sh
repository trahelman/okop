#!/bin/sh
# shellcheck shell=dash
# "Не трогать мой DHCP!" (dont_touch_dhcp) with dnsmasq pointed at sing-box by hand, as docs/dns.md
# describes. okop must leave this setup alone on start, reload, restart and stop: it did not make it,
# so there is nothing of its own to restore.
# Expected: the manual settings survive every command and domains from the lists keep getting fake IPs.

set -eu

. "$(dirname "$0")/../lib.sh"

manual_settings() {
    on_router sh -c 'uci show dhcp.@dnsmasq[0] | grep -E "\.(server|noresolv|cachesize)=" | sort'
}

cleanup() {
    on_router sh -c '
        /etc/init.d/okop stop > /dev/null 2>&1
        uci -q del_list dhcp.@dnsmasq[0].server=127.0.0.42
        uci -q delete dhcp.@dnsmasq[0].noresolv
        uci -q delete dhcp.@dnsmasq[0].cachesize
        uci commit dhcp
        uci set okop.settings.dont_touch_dhcp=0
        uci commit okop
        /etc/init.d/dnsmasq restart 2> /dev/null
        /etc/init.d/okop start > /dev/null 2>&1' || true
}
trap cleanup EXIT

result=0

load_fixture proxy

info "Stopping okop, enabling dont_touch_dhcp and pointing dnsmasq at sing-box by hand"
on_router sh -c '
    /etc/init.d/okop stop > /dev/null 2>&1
    uci set okop.settings.dont_touch_dhcp=1
    uci commit okop
    uci set dhcp.@dnsmasq[0].noresolv=1
    uci set dhcp.@dnsmasq[0].cachesize=0
    uci add_list dhcp.@dnsmasq[0].server=127.0.0.42
    uci commit dhcp
    /etc/init.d/dnsmasq restart 2> /dev/null'
expected="$(manual_settings)"

for command in start reload restart; do
    info "okop $command"
    on_router /etc/init.d/okop "$command" > /dev/null 2>&1
    sleep 2
    wait_okop

    if [ "$(manual_settings)" = "$expected" ]; then
        pass "manual dnsmasq settings survive okop $command"
    else
        fail "okop $command changed the manual dnsmasq settings" || result=1
        printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$(manual_settings)"
    fi

    if wait_for 15 client_gets_fakeip example.com; then
        pass "domains from the lists get fake IPs after okop $command"
    else
        fail "domains from the lists do not get fake IPs after okop $command" || result=1
    fi
done

info "okop stop"
on_router /etc/init.d/okop stop > /dev/null 2>&1
if [ "$(manual_settings)" = "$expected" ]; then
    pass "manual dnsmasq settings survive okop stop"
else
    fail "okop stop changed the manual dnsmasq settings" || result=1
fi

exit "$result"
