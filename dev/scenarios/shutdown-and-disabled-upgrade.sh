#!/bin/sh
# shellcheck shell=dash
# dnsmasq points at sing-box only while okop runs, and the switch is saved in /etc/config/dhcp.
#   - On shutdown okop must give dnsmasq back (it had no STOP, so every reboot was unclean and services
#     starting before okop at boot had no DNS).
#   - A package upgrade runs "start" also for a disabled okop; nothing stopped it before the next reboot,
#     after which dnsmasq pointed at a sing-box nobody started.
# Expected: /etc/config/dhcp of a powered-off router does not point at sing-box, and an upgrade does not
# start a disabled okop.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    dc start router > /dev/null 2>&1 || true
    on_router /etc/init.d/okop enable > /dev/null 2>&1 || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

result=0

load_fixture proxy
wait_for 30 client_gets_fakeip || fail "baseline: client DNS does not go through sing-box"

info "Shutting the router down"
dc stop router > /dev/null 2>&1
if docker cp "$(dc ps -aq router)":/etc/config/dhcp - 2> /dev/null | grep -q "127.0.0.42"; then
    fail "the saved dnsmasq config still points at sing-box after shutdown" || result=1
else
    pass "okop gave dnsmasq back on shutdown"
fi
dc start router > /dev/null
wait_boot
wait_okop

info "Disabling okop and running the package upgrade's start"
on_router /etc/init.d/okop disable > /dev/null 2>&1
on_router sh -c 'PKG_UPGRADE=1 /etc/init.d/okop start' > /dev/null 2>&1
sleep 20

if singbox_running || dnsmasq_uses_singbox; then
    fail "the upgrade started a disabled okop" || result=1
else
    pass "the upgrade does not start a disabled okop"
fi

exit "$result"
