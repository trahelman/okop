#!/bin/sh
# shellcheck shell=dash
# A fresh router has no crontab, and OpenWrt does not start cron at boot without one. okop added its
# lists update job to a crontab that nothing ran, so lists were never updated until a reboot.
# Expected: cron runs after okop adds its job.

set -eu

. "$(dirname "$0")/../lib.sh"

result=0

info "Removing every crontab and stopping cron, as on a fresh router"
on_router sh -c '/etc/init.d/okop stop; /etc/init.d/cron stop; rm -f /etc/crontabs/root' > /dev/null 2>&1

load_fixture proxy

if on_router crontab -l 2> /dev/null | grep -q "okop list_update"; then
    pass "the lists update job is in the crontab"
else
    fail "the lists update job is missing" || result=1
fi

if wait_for 10 on_router pidof crond; then
    pass "cron is running"
else
    fail "cron is not running, the lists are never updated" || result=1
fi

exit "$result"
