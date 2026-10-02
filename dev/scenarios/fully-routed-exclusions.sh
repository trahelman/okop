#!/bin/sh
# shellcheck shell=dash
# A device whose traffic is fully routed through a section: its rules were inserted at the top of the
# mangle chain, ahead of the exclusions. Its NTP went into the proxy with "exclude NTP" enabled, and
# replies of port forwards to it (ct status dnat) were taken into the proxy as well.
# Expected: the device's traffic is routed through the proxy, NTP and port forward replies are not.

set -eu

. "$(dirname "$0")/../lib.sh"

CLIENT_IP=192.168.77.10

cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Packets of the client's UDP marked for the proxy
client_udp_marked() {
    on_router nft list table inet OkopTable |
        grep "saddr $CLIENT_IP " | grep "l4proto udp" | grep -o 'packets [0-9]*' | cut -d' ' -f2
}

# Position of the first mangle rule matching the pattern
mangle_rule_position() {
    on_router nft list chain inet OkopTable mangle | grep -n -- "$1" | head -1 | cut -d: -f1
}

result=0

dc start proxy > /dev/null
load_fixture proxy
info "Routing all traffic of the client through the proxy, NTP excluded"
on_router sh -c "
    uci add_list okop.main.fully_routed_ips='$CLIENT_IP'
    uci set okop.settings.exclude_ntp='1'
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop

if on_client curl -sS -o /dev/null -m 10 https://openwrt.org &&
    dc logs proxy --since 1m 2> /dev/null | grep -q "inbound connection to .*:443"; then
    pass "traffic of the client goes through the proxy"
else
    fail "traffic of the client does not go through the proxy" || result=1
fi

before="$(client_udp_marked)"
on_client busybox ntpd -n -q -p 216.239.35.0 > /dev/null 2>&1 || true
after="$(client_udp_marked)"
if [ -n "$after" ] && [ "$after" = "$before" ]; then
    pass "NTP of the client is not sent to the proxy"
else
    fail "NTP of the client was marked for the proxy ($before -> $after packets)" || result=1
fi

dnat="$(mangle_rule_position 'ct status dnat return')"
ntp="$(mangle_rule_position 'udp dport 123 return')"
routed="$(mangle_rule_position "$CLIENT_IP\|jump fully_routed")"
if [ -n "$dnat" ] && [ -n "$ntp" ] && [ -n "$routed" ] && [ "$routed" -gt "$dnat" ] && [ "$routed" -gt "$ntp" ]; then
    pass "port forward replies and NTP are excluded before the client's rules"
else
    fail "the client's rules come before the exclusions (dnat $dnat, ntp $ntp, client $routed)" || result=1
fi

exit "$result"
