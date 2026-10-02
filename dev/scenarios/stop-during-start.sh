#!/bin/sh
# shellcheck shell=dash
# start, stop and reload were not serialized: a stop arriving while a start was still running (LuCI
# buttons, Save & Apply twice, interface monitoring at boot) cleaned up first, and then the start went on
# and installed the interception again, leaving a half-running okop.
# Expected: whatever the order, the last command wins: after "start, then stop" okop is fully off.

set -eu

. "$(dirname "$0")/../lib.sh"

result=0

load_fixture proxy

info "Stopping okop while a start is still running"
on_router sh -c '
    okop stop > /dev/null 2>&1
    okop start > /dev/null 2>&1 &
    sleep 3
    okop stop > /dev/null 2>&1
    wait'
sleep 5

if on_router nft list table inet OkopTable > /dev/null 2>&1; then
    fail "the nft table is installed after the stop" || result=1
else
    pass "no nft table after the stop"
fi

if singbox_running; then
    fail "sing-box runs after the stop" || result=1
else
    pass "sing-box is stopped"
fi

if dnsmasq_uses_singbox; then
    fail "dnsmasq points at sing-box after the stop" || result=1
else
    pass "dnsmasq is given back"
fi

info "Killing a running start with TERM, as procd does"
on_router sh -c '
    okop stop > /dev/null 2>&1
    okop start > /dev/null 2>&1 &
    pid=$!
    sleep 4
    kill -TERM "$pid"
    wait'
sleep 5

if on_router nft list table inet OkopTable > /dev/null 2>&1; then
    fail "a start killed with TERM left the nft table" || result=1
else
    pass "a start killed with TERM rolls back the interception"
fi

on_router /etc/init.d/okop start > /dev/null 2>&1
exit "$result"
