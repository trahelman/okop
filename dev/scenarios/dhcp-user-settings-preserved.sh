#!/bin/sh
# shellcheck shell=dash
# User settings in /etc/config/dhcp: a forwarding for a specific domain, a general upstream server, other options.
# Expected: the forwarding keeps working while dnsmasq uses sing-box, and the dnsmasq section is exactly
# the same after okop is stopped, including settings added while okop was running.
# Options are compared sorted: their order inside the section does not matter, the order of list items does.

set -eu

. "$(dirname "$0")/../lib.sh"

dnsmasq_section() {
    on_router uci show dhcp.@dnsmasq[0]
}

# forwarded.test is forwarded to a server that always answers 1.2.3.4
forwarding_works() {
    [ "$(on_client dig +short +time=2 +tries=1 "@$ROUTER_LAN_IP" forwarded.test A)" = "1.2.3.4" ]
}

remove_test_settings() {
    on_router sh -c '
        for key in server okop_server; do
            uci -q del_list dhcp.@dnsmasq[0].$key="9.9.9.9"
            uci -q del_list dhcp.@dnsmasq[0].$key="/forwarded.test/127.0.0.1#5353"
            uci -q del_list dhcp.@dnsmasq[0].$key="/added.test/10.0.0.1"
        done
        uci -q delete dhcp.@dnsmasq[0].logqueries
        uci commit dhcp
        [ -f /tmp/fake-dns.pid ] && kill "$(cat /tmp/fake-dns.pid)" && rm -f /tmp/fake-dns.pid
        true'
}

# okop is stopped first, so that its backup of dnsmasq settings is restored before test settings are removed
cleanup() {
    on_router /etc/init.d/okop stop > /dev/null 2>&1 || true
    remove_test_settings || true
    on_router /etc/init.d/okop start > /dev/null 2>&1 || true
}

show_state() {
    on_router sh -c 'uci show dhcp.@dnsmasq[0] | grep -E "server|noresolv|cachesize"; logread -e okop | grep -E "dnsmasq|guard" | tail -5'
}

trap cleanup EXIT

result=0

info "Stopping okop and adding user settings to dhcp"
on_router /etc/init.d/okop stop > /dev/null 2>&1 || true
remove_test_settings
on_router sh -c '
    # A DNS server that answers everything with 1.2.3.4
    dnsmasq -C /dev/null --port=5353 --listen-address=127.0.0.1 --bind-interfaces --no-resolv --no-hosts \
        --address=/#/1.2.3.4 --pid-file=/tmp/fake-dns.pid
    uci add_list dhcp.@dnsmasq[0].server="9.9.9.9"
    uci add_list dhcp.@dnsmasq[0].server="/forwarded.test/127.0.0.1#5353"
    uci set dhcp.@dnsmasq[0].logqueries="1"
    uci commit dhcp
    /etc/init.d/dnsmasq restart'
before="$(dnsmasq_section | sort)"

load_fixture proxy
wait_for 30 client_gets_fakeip || { show_state; fail "baseline: client DNS does not go through sing-box"; }

if forwarding_works; then
    pass "domain forwarding works while dnsmasq uses sing-box"
else
    fail "domain forwarding is lost while dnsmasq uses sing-box" || result=1
    show_state
fi

info "Adding a forwarding while okop is running"
on_router sh -c 'uci add_list dhcp.@dnsmasq[0].server="/added.test/10.0.0.1"; uci commit dhcp'

info "Stopping okop"
on_router /etc/init.d/okop stop > /dev/null 2>&1
after="$(dnsmasq_section | sort)"
expected="$(printf '%s\n' "$before" | sed "s|'/forwarded.test/127.0.0.1#5353'|& '/added.test/10.0.0.1'|")"

if [ "$after" = "$expected" ]; then
    pass "dnsmasq settings are restored exactly, including the added forwarding"
else
    fail "dnsmasq settings differ after okop stop" || result=1
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$after"
fi

exit "$result"
