#!/bin/sh
# shellcheck shell=dash
# sing-box stops while okop is running, then comes back.
# Expected: LAN DNS falls back to the upstream servers and returns to sing-box when it is back.

set -eu

. "$(dirname "$0")/../lib.sh"

result=0

dc start proxy > /dev/null
load_fixture proxy
wait_for 15 client_gets_fakeip || fail "baseline: client DNS does not go through sing-box"

info "Stopping sing-box"
on_router /etc/init.d/sing-box stop

if wait_for 30 client_resolves; then
    pass "client DNS falls back to the upstream servers"
else
    fail "client DNS is broken while sing-box is down" || result=1
fi

info "Starting sing-box"
on_router /etc/init.d/sing-box start

if wait_for 30 client_gets_fakeip; then
    pass "client DNS goes through sing-box again"
else
    fail "client DNS does not return to sing-box" || result=1
fi

exit "$result"
