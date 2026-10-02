#!/bin/sh
# shellcheck shell=dash
# HTTPUpgrade links are documented in String-example.md and supported by sing-box, but the backend
# handled only tcp/raw/ws/grpc. Such a link produced an outbound with no transport at all: the UI
# reported the link valid, okop started, and that section simply never connected.
# Expected: the transport object in the generated config matches the link.

set -eu

. "$(dirname "$0")/../lib.sh"

CONFIG=/etc/sing-box/config.json

outbound_transport() {
    on_router jq -c '[.outbounds[] | select(.type == "vless")][0].transport' "$CONFIG"
}

apply_proxy_string() {
    on_router sh -c "
        uci set okop.main.proxy_config_type=url
        uci set okop.main.proxy_string='$1'
        uci commit okop
        /etc/init.d/okop restart" > /dev/null 2>&1
    wait_okop
}

# Leave the router on a working proxy for the scenarios that follow
cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}

trap cleanup EXIT

result=0

load_fixture proxy

info "A vless link with an HTTPUpgrade transport"
apply_proxy_string 'vless://2b98f144-847f-42f7-8798-e1a32d27bdc7@172.31.77.3:47154?type=httpupgrade&encryption=none&path=%2Fhttpupgradepath&host=google.com&security=none#hu'

transport="$(outbound_transport)"
if [ "$transport" = 'null' ]; then
    fail "the outbound has no transport, an HTTPUpgrade link produces a section that cannot connect" || result=1
else
    pass "the outbound has a transport"
fi

if on_router jq -e '[.outbounds[] | select(.type == "vless")][0].transport.type == "httpupgrade"' "$CONFIG" > /dev/null; then
    pass "the transport type is httpupgrade"
else
    fail "the transport type is not httpupgrade: $transport" || result=1
fi

# The path is percent-encoded in the link and must be decoded exactly once
if on_router jq -e '[.outbounds[] | select(.type == "vless")][0].transport.path == "/httpupgradepath"' "$CONFIG" > /dev/null; then
    pass "the percent-encoded path is decoded"
else
    fail "the path is wrong: $transport" || result=1
fi

if on_router jq -e '[.outbounds[] | select(.type == "vless")][0].transport.host == "google.com"' "$CONFIG" > /dev/null; then
    pass "the host is taken from the link"
else
    fail "the host is wrong: $transport" || result=1
fi

exit "$result"
