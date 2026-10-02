#!/bin/sh
# shellcheck shell=dash
# Lists are downloaded via a proxy that is down, GitHub itself is reachable.
# Expected: without download_lists_direct_fallback the lists are not downloaded directly, with it they are.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    on_router sh -c 'uci set okop.settings.download_lists_direct_fallback=0; uci commit okop' || true
    dc start proxy > /dev/null
}
trap cleanup EXIT

# Every cached list of the fixture has rules
lists_downloaded() {
    on_router sh -c '
        for f in /etc/okop/rulesets/*.srs; do
            sing-box rule-set decompile "$f" -o /tmp/list.json &&
                [ "$(jq ".rules | length" /tmp/list.json)" -gt 0 ] || exit 1
        done'
}

set_direct_fallback() {
    on_router sh -c "uci set okop.settings.download_lists_direct_fallback=$1; uci commit okop"
}

result=0

dc start proxy > /dev/null
load_fixture proxy

info "Stopping the proxy and removing downloaded lists"
dc stop proxy > /dev/null
set_direct_fallback 0
on_router sh -c 'rm -rf /etc/okop/rulesets/*'
on_router /etc/init.d/okop restart > /dev/null 2>&1
wait_okop

# The update started with okop retries while the proxy is down. Settings are changed the way LuCI does it:
# Save & Apply restarts okop.
info "Waiting for the start-time update without the direct fallback"
if wait_for 90 lists_downloaded; then
    fail "lists were downloaded directly although the direct fallback is disabled" || result=1
else
    pass "lists are not downloaded directly without the direct fallback"
fi

info "Enabling the direct fallback and restarting okop"
set_direct_fallback 1
on_router /etc/init.d/okop restart > /dev/null 2>&1
if wait_for 120 lists_downloaded; then
    pass "lists are downloaded directly with the direct fallback"
else
    fail "lists are not downloaded with the direct fallback" || result=1
fi

exit "$result"
