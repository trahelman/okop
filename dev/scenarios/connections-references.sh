#!/bin/sh
# shellcheck shell=dash
# References between sections and connections.
#   - A spare connection or group that nothing uses yet and is unfinished stopped okop from starting.
#   - A connection used only by a JSON connection (detour) was left out as unused.
#   - A section naming a connection that does not exist, and groups containing each other, gave a
#     sing-box error about tags that does not say which setting is wrong.
# Expected: the spare connection is left out and okop starts; the broken references are named in the
# log, okop does not start and the LAN keeps working.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

last_fatal() {
    on_router sh -c 'logread -e okop | grep fatal | tail -1'
}

restart_with() {
    on_router sh -c "$1; uci commit okop; /etc/init.d/okop restart" > /dev/null 2>&1
    sleep 2
}

result=0

load_fixture proxy
info "A spare connection without a link that nothing uses"
restart_with "uci set okop.spare=outbound; uci set okop.spare.type=url"
wait_okop
if singbox_stable && wait_for 15 client_gets_fakeip example.com; then
    pass "okop starts and routes with an unused unfinished connection"
else
    fail "okop did not start: $(last_fatal)" || result=1
fi

load_fixture proxy
info "A JSON connection chaining through a connection nothing else uses, an unused group with a missing member"
restart_with "
    uci set okop.hop=outbound; uci set okop.hop.type=url
    uci set okop.hop.url='ss://YWVzLTEyOC1nY206b2tvcC1kZXY=@172.31.77.3:8388#hop'
    uci set okop.chain=outbound; uci set okop.chain.type=json
    uci set okop.chain.json='{\"type\":\"socks\",\"server\":\"172.31.77.3\",\"server_port\":1080,\"detour\":\"hop-out\"}'
    uci set okop.main.outbound=chain
    uci set okop.leftover=outbound; uci set okop.leftover.type=fallback; uci add_list okop.leftover.members=gone"
wait_okop
if singbox_stable && wait_for 15 client_gets_fakeip example.com &&
    on_router jq -e '.outbounds[] | select(.tag == "hop-out")' /etc/sing-box/config.json > /dev/null; then
    pass "the connection used only as a detour is generated, the unused broken group does not stop okop"
else
    fail "okop did not start: $(last_fatal)" || result=1
fi

load_fixture proxy
info "A section naming a connection that does not exist"
restart_with "uci set okop.main.outbound=gone"
sleep 10
if last_fatal | grep -q "uses the connection 'gone', which does not exist"; then
    pass "the missing connection is named in the log"
else
    fail "unexpected log: $(last_fatal)" || result=1
fi
if wait_for 15 client_resolves; then
    pass "client DNS works"
else
    fail "client has no DNS" || result=1
fi

load_fixture proxy
info "Two groups containing each other"
restart_with "
    uci set okop.a=outbound; uci set okop.a.type=fallback; uci add_list okop.a.members=b
    uci set okop.b=outbound; uci set okop.b.type=selector; uci add_list okop.b.members=a
    uci add_list okop.b.members=dev_proxy
    uci set okop.main.outbound=a"
sleep 10
if last_fatal | grep -q "Connection groups contain each other: a → b → a"; then
    pass "the cycle is named in the log"
else
    fail "unexpected log: $(last_fatal)" || result=1
fi
if wait_for 15 client_resolves; then
    pass "client DNS works"
else
    fail "client has no DNS" || result=1
fi

exit "$result"
