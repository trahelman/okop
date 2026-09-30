#!/bin/sh
# shellcheck shell=dash
# okop is started again without a clean stop (crash, OOM kill, a second "start"), leaving its /tmp state behind.
# Upstream Podkop issue #356: user lists were left out of the sing-box config after such a start.
# Expected: user domains keep working, a domain removed from the list stops being routed,
# and nftables rules are not duplicated.

set -eu

. "$(dirname "$0")/../lib.sh"

set_user_domain() {
    on_router sh -c "uci set okop.main.user_domain_list_type=text; uci set okop.main.user_domains_text='$1'; uci commit okop"
}

nft_rule_count() {
    on_router sh -c 'nft list table inet OkopTable | grep -c counter'
}

start_without_stop() {
    info "Starting okop again without stopping it"
    on_router /etc/init.d/okop start > /dev/null 2>&1
    sleep 2
    wait_okop
}

result=0

dc start proxy > /dev/null
load_fixture proxy
set_user_domain "first.example.com"
on_router /etc/init.d/okop restart > /dev/null 2>&1
sleep 2
wait_okop
wait_for 15 client_gets_fakeip first.example.com || fail "baseline: user domain is not routed"
rules_before="$(nft_rule_count)"

start_without_stop

if wait_for 15 client_gets_fakeip first.example.com; then
    pass "user domain is routed after start without stop"
else
    fail "user domain is not routed after start without stop" || result=1
fi

if [ "$(nft_rule_count)" = "$rules_before" ]; then
    pass "nftables rules are not duplicated"
else
    fail "nftables rules are duplicated: $rules_before before, $(nft_rule_count) after" || result=1
fi

info "Replacing the user domain"
set_user_domain "second.example.com"
start_without_stop

if wait_for 15 client_gets_fakeip second.example.com; then
    pass "new user domain is routed"
else
    fail "new user domain is not routed" || result=1
fi

if client_gets_fakeip first.example.com; then
    fail "removed user domain is still routed" || result=1
else
    pass "removed user domain is not routed anymore"
fi

exit "$result"
