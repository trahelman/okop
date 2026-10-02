#!/bin/sh
# shellcheck shell=dash
# The dnsmasq settings are changed while okop is running. A domain forwarding edited in the meantime came
# back in its old form on stop next to the new one. With sing-box removed from the servers by hand, the
# next start took okop's own noresolv and cachesize for the user's and backed them up over the originals.
# Expected: stop restores the user's settings as they are at that moment.

set -eu

. "$(dirname "$0")/../lib.sh"

OLD_FORWARDING=/corp.test/10.0.0.53
NEW_FORWARDING=/corp.test/10.0.0.54

remove_test_settings() {
    on_router sh -c "
        for key in server okop_server; do
            uci -q del_list dhcp.@dnsmasq[0].\$key='$OLD_FORWARDING'
            uci -q del_list dhcp.@dnsmasq[0].\$key='$NEW_FORWARDING'
        done
        uci -q delete dhcp.@dnsmasq[0].cachesize
        uci commit dhcp"
}

cleanup() {
    on_router /etc/init.d/okop stop > /dev/null 2>&1 || true
    remove_test_settings || true
    on_router /etc/init.d/okop start > /dev/null 2>&1 || true
}
trap cleanup EXIT

dnsmasq_option() {
    on_router uci -q get "dhcp.@dnsmasq[0].$1" || true
}

servers_contain() {
    printf '%s\n' "$servers" | tr ' ' '\n' | grep -qxF "$1"
}

result=0

info "Stopping okop and adding a forwarding and a cache size to dhcp"
on_router /etc/init.d/okop stop > /dev/null 2>&1 || true
remove_test_settings
on_router sh -c "
    uci add_list dhcp.@dnsmasq[0].server='$OLD_FORWARDING'
    uci set dhcp.@dnsmasq[0].cachesize='1000'
    uci commit dhcp"
noresolv_before="$(dnsmasq_option noresolv)"

load_fixture proxy
info "Editing the forwarding while okop is running"
on_router sh -c "
    uci del_list dhcp.@dnsmasq[0].server='$OLD_FORWARDING'
    uci add_list dhcp.@dnsmasq[0].server='$NEW_FORWARDING'
    uci commit dhcp"
on_router /etc/init.d/okop stop > /dev/null 2>&1

servers="$(dnsmasq_option server)"
if servers_contain "$NEW_FORWARDING" && ! servers_contain "$OLD_FORWARDING"; then
    pass "the edited forwarding is restored as edited"
else
    fail "forwardings after stop: $servers" || result=1
fi

info "Removing sing-box from the dnsmasq servers by hand while okop is running"
on_router /etc/init.d/okop start > /dev/null 2>&1
wait_okop
on_router sh -c "uci del_list dhcp.@dnsmasq[0].server='127.0.0.42'; uci commit dhcp"
on_router /etc/init.d/okop restart > /dev/null 2>&1
wait_okop
on_router /etc/init.d/okop stop > /dev/null 2>&1

cachesize="$(dnsmasq_option cachesize)"
noresolv="$(dnsmasq_option noresolv)"
if [ "$cachesize" = "1000" ] && [ "$noresolv" = "$noresolv_before" ]; then
    pass "cachesize and noresolv are restored after a manual change and a restart"
else
    fail "cachesize '$cachesize' (expected 1000), noresolv '$noresolv' (expected '$noresolv_before')" || result=1
fi

exit "$result"
