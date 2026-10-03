#!/bin/sh
# shellcheck shell=dash
# A fallback connection group: a primary connection and a backup one, then a VPN interface with a proxy
# as its backup.
# Expected: traffic goes through the primary connection while it responds, moves to the backup when the
# primary stops responding, comes back once the primary responds again. A VPN that is down falls back
# to the proxy.

set -eu

. "$(dirname "$0")/../lib.sh"

PRIMARY_PORT=8388

unblock_primary() {
    on_router nft delete table inet okop_scenario 2> /dev/null || true
}

cleanup() {
    unblock_primary
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

# The member the group currently uses, as reported by sing-box
group_now() {
    on_router sh -c "curl -s -m 5 http://$ROUTER_LAN_IP:9090/proxies/fb-out | jq -r '.now // empty'"
}

group_uses() {
    [ "$(group_now)" = "$1-out" ]
}

# Connections from the router to the primary connection's server are dropped, the backup's are not
block_primary() {
    on_router sh -c "
        nft add table inet okop_scenario
        nft add chain inet okop_scenario output '{ type filter hook output priority 0; }'
        nft add rule inet okop_scenario output ip daddr 172.31.77.3 tcp dport $PRIMARY_PORT drop"
}

result=0

dc start proxy > /dev/null
load_fixture proxy
info "Routing through a fallback group: shadowsocks first, SOCKS as the backup"
on_router sh -c "
    uci set okop.primary=outbound
    uci set okop.primary.type=url
    uci set okop.primary.url='ss://YWVzLTEyOC1nY206b2tvcC1kZXY=@172.31.77.3:$PRIMARY_PORT#primary'
    uci set okop.backup=outbound
    uci set okop.backup.type=url
    uci set okop.backup.url='socks5://172.31.77.3:1080#backup'
    uci set okop.fb=outbound
    uci set okop.fb.type=fallback
    uci set okop.fb.check_interval=10s
    uci add_list okop.fb.members=primary
    uci add_list okop.fb.members=backup
    uci set okop.main.outbound=fb
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop

if wait_for 15 group_uses primary && wait_for 15 client_fetches https://example.com; then
    pass "traffic goes through the primary connection"
else
    fail "the group does not use the primary connection: '$(group_now)'" || result=1
fi

info "The primary connection stops responding"
block_primary
if wait_for 60 group_uses backup; then
    pass "the group switches to the backup"
else
    fail "the group did not switch to the backup: '$(group_now)'" || result=1
fi

if wait_for 15 client_fetches https://example.com &&
    dc logs proxy --since 30s 2> /dev/null | grep -q "inbound/socks.*example.com"; then
    pass "traffic goes through the backup"
else
    fail "traffic does not go through the backup" || result=1
fi

info "The primary connection responds again"
unblock_primary
if wait_for 90 group_uses primary; then
    pass "the group comes back to the primary connection"
else
    fail "the group did not come back to the primary connection: '$(group_now)'" || result=1
fi

info "A VPN interface that is down, with the proxy as the backup"
on_router sh -c "
    uci set okop.vpn=outbound
    uci set okop.vpn.type=interface
    uci set okop.vpn.interface=wg0
    uci delete okop.fb.members
    uci add_list okop.fb.members=vpn
    uci add_list okop.fb.members=backup
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop

if wait_for 60 group_uses backup && wait_for 15 client_fetches https://example.com; then
    pass "a VPN that is down falls back to the proxy"
else
    fail "the group stays on the VPN that is down: '$(group_now)'" || result=1
fi

exit "$result"
