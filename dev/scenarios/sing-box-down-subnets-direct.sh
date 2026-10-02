#!/bin/sh
# shellcheck shell=dash
# sing-box stays down while okop is running. DNS fell back to the upstream servers, but connections to
# subnets from the lists (Telegram, Discord, user subnets) were still sent to the dead tproxy port, so
# those services were cut off until sing-box came back.
# Expected: while sing-box is down they go directly, once it is back they go through it again.

set -eu

. "$(dirname "$0")/../lib.sh"

SUBNET_HOST=1.1.1.1

cleanup() {
    on_router /etc/init.d/sing-box start > /dev/null 2>&1 || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

subnet_host_reachable() {
    on_client curl -sk -o /dev/null -m 5 "https://$SUBNET_HOST"
}

lists_routed_to_singbox() {
    on_router ip -4 rule list | grep -q "lookup okop"
}

result=0

dc start proxy > /dev/null
load_fixture proxy
info "Routing $SUBNET_HOST as a user subnet"
on_router sh -c "
    uci set okop.main.user_subnet_list_type='dynamic'
    uci add_list okop.main.user_subnets='$SUBNET_HOST'
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop
wait_for 30 subnet_host_reachable || fail "baseline: $SUBNET_HOST is not reachable through the proxy"

info "Stopping sing-box"
on_router /etc/init.d/sing-box stop

if wait_for 40 subnet_host_reachable && ! lists_routed_to_singbox; then
    pass "the user subnet is reachable directly while sing-box is down"
else
    fail "the user subnet is cut off while sing-box is down" || result=1
fi

info "Starting sing-box"
on_router /etc/init.d/sing-box start

if wait_for 40 lists_routed_to_singbox && wait_for 30 client_gets_fakeip && subnet_host_reachable; then
    pass "the lists are routed through sing-box again"
else
    fail "the lists are not routed through sing-box after it is back" || result=1
fi

exit "$result"
