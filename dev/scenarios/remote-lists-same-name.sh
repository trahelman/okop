#!/bin/sh
# shellcheck shell=dash
# Remote lists are named after their file: two different URLs with the same file name got the same rule set
# tag and sing-box rejected the config; the same URL added twice did too. A URL with a query string
# (list.srs?raw=true, a common GitHub form) was taken for a plain-text list and routed nothing.
# Expected: okop starts, each distinct list has its own rule set, the duplicate is ignored.

set -eu

. "$(dirname "$0")/../lib.sh"

URL='https://github.com/itdoginfo/allow-domains/releases/latest/download/hdrezka.srs'

cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

result=0

load_fixture proxy
info "Adding the same list twice, and once more with ?raw=true"
on_router sh -c "
    uci add_list okop.main.remote_domain_lists='$URL'
    uci add_list okop.main.remote_domain_lists='$URL'
    uci add_list okop.main.remote_domain_lists='$URL?raw=true'
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop

if singbox_stable; then
    pass "okop starts with lists sharing a file name"
else
    fail "okop did not start: $(on_router sh -c 'logread -e okop | grep fatal | tail -1')" || result=1
fi

tags="$(on_router jq -r '.route.rule_set[].tag | select(contains("hdrezka"))' /etc/sing-box/config.json 2> /dev/null | sort -u | wc -l)"
if [ "$tags" -eq 2 ]; then
    pass "the two distinct lists have their own rule sets, the duplicate is ignored"
else
    fail "expected 2 hdrezka rule sets, got $tags" || result=1
fi

if wait_for 60 client_gets_fakeip rezka.ag; then
    pass "the list with ?raw=true is used as a rule set"
else
    fail "domains of the lists are not routed" || result=1
fi

exit "$result"
