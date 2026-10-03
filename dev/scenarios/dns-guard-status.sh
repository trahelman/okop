#!/bin/sh
# shellcheck shell=dash
# The dashboard shows what the DNS guard is doing: whether DNS and the lists go through sing-box, and
# since when they bypass it.
# Expected: "okop get_dns_guard_status" reports the actual state and the time of the last switch.

set -eu

. "$(dirname "$0")/../lib.sh"

UPSTREAM="77.88.8.8"

block_upstream() {
    on_router sh -c "
        nft add table inet devblock
        nft add chain inet devblock out '{ type filter hook output priority 0; }'
        nft add rule inet devblock out ip daddr $UPSTREAM udp dport 53 drop
        nft add rule inet devblock out ip daddr $UPSTREAM tcp dport 53 drop"
}

unblock_upstream() {
    on_router nft delete table inet devblock 2> /dev/null || true
}

cleanup() {
    unblock_upstream
    on_router /etc/init.d/sing-box start > /dev/null 2>&1 || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

guard_status() {
    on_router /usr/bin/okop get_dns_guard_status
}

guard_field() {
    guard_status | jq -r ".$1"
}

guard_state_is() {
    [ "$(guard_field state)" = "$1" ]
}

router_time() {
    on_router date +%s
}

# The guard records the time at the end of the check that switched, a moment after the switch itself
guard_switched_after() {
    local status
    status="$(guard_status)"
    [ "$(echo "$status" | jq -r .state)" = "$1" ] && [ "$(echo "$status" | jq -r .since)" -ge "$2" ]
}

result=0

load_fixture proxy
wait_for 30 client_gets_fakeip || fail "baseline: client DNS does not go through sing-box"

if wait_for 15 guard_state_is ok && [ "$(guard_field running)" = 1 ] && [ "$(guard_field since)" -gt 0 ]; then
    pass "the guard reports DNS and the lists going through sing-box"
else
    fail "unexpected status with sing-box working: $(guard_status)" || result=1
fi

info "Blocking the DNS server sing-box forwards to"
blocked_at="$(router_time)"
block_upstream

if wait_for 90 guard_switched_after dns_server_down "$blocked_at"; then
    pass "the guard reports the unreachable DNS server and when it switched"
else
    fail "unexpected status with the DNS server blocked: $(guard_status)" || result=1
fi

info "Unblocking the DNS server"
unblock_upstream

if wait_for 60 guard_state_is ok; then
    pass "the guard reports sing-box DNS again"
else
    fail "unexpected status after the DNS server is back: $(guard_status)" || result=1
fi

info "Stopping sing-box"
stopped_at="$(router_time)"
on_router /etc/init.d/sing-box stop

if wait_for 40 guard_switched_after sing_box_down "$stopped_at"; then
    pass "the guard reports sing-box down and when it switched"
else
    fail "unexpected status with sing-box stopped: $(guard_status)" || result=1
fi

info "Starting sing-box"
on_router /etc/init.d/sing-box start

if wait_for 40 guard_state_is ok; then
    pass "the guard reports sing-box back"
else
    fail "unexpected status after sing-box is back: $(guard_status)" || result=1
fi

info "Stopping okop"
on_router /etc/init.d/okop stop > /dev/null 2>&1

if guard_state_is stopped && [ "$(guard_field running)" = 0 ]; then
    pass "the guard reports itself stopped with okop"
else
    fail "unexpected status with okop stopped: $(guard_status)" || result=1
fi

exit "$result"
