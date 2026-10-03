#!/bin/sh
# shellcheck shell=dash
# A configuration in the layout of okop 0.6 and earlier: Proxy (link, URLTest) and VPN sections hold their
# connections themselves, the list download names a section, a mixed proxy is set on a section.
# Expected: an upgrade (uci-defaults) moves every connection into a connection of its own, the sections
# refer to them, and okop routes as before. A second start changes nothing.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

opt() {
    on_router uci -q get "okop.$1" || true
}

expect() {
    local what="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$what"
    else
        fail "$what: '$actual', expected '$expected'" || result=1
    fi
}

result=0

info "Upgrading with a configuration in the old layout"
on_router sh -c '
    /etc/init.d/okop stop
    cp /root/fixtures/legacy-sections.uci /etc/config/okop
    sh /opt/okop/etc/uci-defaults/60_okop_outbounds' > /dev/null 2>&1

expect "the link section uses its own connection" "$(opt main.connection_type) $(opt main.outbound)" "outbound main_out"
expect "the link connection" "$(opt main_out) $(opt main_out.type)" "outbound url"
expect "the link is kept" "$(opt main_out.url)" "ss://YWVzLTEyOC1nY206b2tvcC1kZXY=@172.31.77.3:8388#dev-proxy"
expect "the mixed proxy moves to the connection" "$(opt main_out.mixed_proxy_enabled) $(opt main_out.mixed_proxy_port) $(opt main.mixed_proxy_port)" "1 2080 "
expect "the URLTest section becomes a group" "$(opt multi.outbound) $(opt multi_out.type) $(opt multi_out.members)" "multi_out urltest multi_1 multi_2"
expect "URLTest settings are kept" "$(opt multi_out.check_interval) $(opt multi_out.tolerance)" "1m 100"
expect "URLTest links become connections" "$(opt multi_2.type) $(opt multi_2.url)" "url ss://YWVzLTEyOC1nY206b2tvcC1kZXY=@172.31.77.3:8388#dev-proxy-2"
expect "the VPN section becomes an interface connection" "$(opt vpn.outbound) $(opt vpn_out.type) $(opt vpn_out.interface) $(opt vpn_out.domain_resolver_dns_server)" "vpn_out interface wg0 8.8.8.8"
expect "the block section is left as it is" "$(opt blk.connection_type) $(opt blk.outbound)" "block "
expect "lists are downloaded through the connection" "$(opt settings.download_lists_via_outbound) $(opt settings.download_lists_via_proxy_section)" "main_out "

left="$(on_router uci show okop |
    grep -cE '^okop\.(main|multi|vpn|blk)\.(proxy_string|proxy_config_type|urltest_[a-z_]*|interface|domain_resolver_[a-z_]*|mixed_proxy_[a-z]*)=' ||
    true)"
expect "no connection options are left in sections" "$left" "0"

on_router /etc/init.d/okop start > /dev/null 2>&1
sleep 2
wait_okop

if singbox_stable; then
    pass "okop starts with the converted configuration"
else
    fail "okop did not start: $(on_router sh -c 'logread -e okop | grep fatal | tail -1')" || result=1
fi

for domain in example.com wikipedia.org; do
    if wait_for 30 client_gets_fakeip "$domain"; then
        pass "$domain is routed"
    else
        fail "$domain is not routed" || result=1
    fi
done

if wait_for 15 on_client curl -s -o /dev/null -m 10 -x "socks5h://$ROUTER_LAN_IP:2080" https://openwrt.org; then
    pass "the mixed proxy works"
else
    fail "the mixed proxy does not work" || result=1
fi

before="$(on_router uci export okop)"
on_router /etc/init.d/okop restart > /dev/null 2>&1
sleep 2
wait_okop
if [ "$(on_router uci export okop)" = "$before" ]; then
    pass "a second start changes nothing"
else
    fail "a second start changed the configuration" || result=1
fi

exit "$result"
