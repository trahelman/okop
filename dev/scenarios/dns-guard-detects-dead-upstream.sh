#!/bin/sh
# shellcheck shell=dash
# sing-box answers the fakeip test domain from its own fake-IP pool, without contacting anything, so a
# live sing-box always passes that probe. Everything that is not in a routed list is forwarded to
# dns_server, so when that server is unreachable -- a blocked public resolver is the common case --
# the whole LAN stops resolving while sing-box looks perfectly healthy.
# Expected: the DNS guard notices and falls back to the upstream servers, then switches back.

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

show_state() {
    on_router sh -c 'uci show dhcp.@dnsmasq[0] | grep -E "server|noresolv"; logread -e okop | grep -E "guard|dnsmasq" | tail -6'
}

cleanup() {
    unblock_upstream
}

trap cleanup EXIT

result=0

load_fixture proxy
wait_for 30 client_gets_fakeip || { show_state; fail "baseline: client DNS does not go through sing-box"; }
wait_for 15 client_resolves || { show_state; fail "baseline: client does not resolve a domain outside the lists"; }

info "Blocking the DNS server sing-box forwards to"
block_upstream

# The guard needs several failed probes in a row before it switches dnsmasq back
i=0
while [ "$i" -lt 60 ] && dnsmasq_uses_singbox; do
    sleep 1
    i=$((i + 1))
done

if dnsmasq_uses_singbox; then
    fail "the DNS guard left dnsmasq on sing-box although sing-box cannot resolve anything" || result=1
    show_state
else
    pass "the DNS guard switched dnsmasq back when sing-box stopped resolving"
fi

if wait_for 30 client_resolves; then
    pass "client DNS works again after the fallback"
else
    fail "client still has no DNS after the fallback" || result=1
    show_state
fi

info "Unblocking the DNS server"
unblock_upstream

if wait_for 60 dnsmasq_uses_singbox; then
    pass "dnsmasq goes back to sing-box once it can resolve again"
else
    fail "dnsmasq does not go back to sing-box after the upstream recovered" || result=1
    show_state
fi

if wait_for 30 client_gets_fakeip example.com; then
    pass "a user domain is routed again"
else
    fail "a user domain is not routed after the upstream recovered" || result=1
    show_state
fi

exit "$result"
