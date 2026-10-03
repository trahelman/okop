#!/bin/sh
# shellcheck shell=dash
# Users paste the output of the diagnostics into chats and issues. It printed the Clash API secret,
# private DoH paths, credentials of non-PPPoE WAN protocols and keys from outbound JSON in the clear.
# Expected: none of the planted secrets appears in show_config, show_sing_box_config, check_proxy or
# global_check.

set -eu

. "$(dirname "$0")/../lib.sh"

SECRETS="okop-dev S3CRETKEY abc123doh wanpass123 wanuser123 socksuser123 sockspass123"

cleanup() {
    on_router sh -c 'uci -q delete network.wan.username; uci -q delete network.wan.password; uci commit network' || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

result=0

load_fixture proxy
info "Planting secrets in the settings"
on_router sh -c "
    uci set okop.settings.enable_yacd=1
    uci set okop.settings.enable_yacd_wan_access=1
    uci set okop.settings.yacd_secret_key=S3CRETKEY
    uci set okop.settings.dns_type=doh
    uci set okop.settings.dns_server=dns.adguard-dns.com/dns-query/abc123doh
    uci set okop.socks=outbound
    uci set okop.socks.type=json
    uci set okop.socks.json='{\"type\":\"socks\",\"server\":\"5.6.7.8\",\"server_port\":1080,\"username\":\"socksuser123\",\"password\":\"sockspass123\"}'
    uci set okop.vpn=section
    uci set okop.vpn.connection_type=outbound
    uci set okop.vpn.outbound=socks
    uci add_list okop.vpn.user_domains=example.net
    uci set okop.vpn.user_domain_list_type=dynamic
    uci commit okop
    uci set network.wan.username=wanuser123
    uci set network.wan.password=wanpass123
    uci commit network
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop
singbox_running || fail "baseline: okop did not start with the planted settings"

for command in show_config show_sing_box_config check_proxy global_check; do
    output="$(on_router okop "$command" 2>&1 || true)"
    leaked=""
    for secret in $SECRETS; do
        printf '%s' "$output" | grep -q "$secret" && leaked="$leaked $secret"
    done
    if [ -z "$leaked" ]; then
        pass "okop $command does not print the secrets"
    else
        fail "okop $command prints:$leaked" || result=1
    fi
done

exit "$result"
