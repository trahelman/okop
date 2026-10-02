#!/bin/sh
# shellcheck shell=dash
# "service okop reload" (what interface monitoring runs on every WAN reconnect), then stop.
# rc.common holds procd's lock on fd 1000 during reload; a background job inheriting it keeps the lock
# and every later init.d action waits for it.
# Expected: stop, start and restart after a reload each finish within 30 seconds.

set -eu

. "$(dirname "$0")/../lib.sh"

# Prints the seconds the init.d action took, or "timeout" after 30 seconds
time_init_action() {
    on_router sh -c '
        ( /etc/init.d/okop "$1" > /dev/null 2>&1 ) &
        pid=$!
        i=0
        while kill -0 "$pid" 2> /dev/null && [ "$i" -lt 30 ]; do
            sleep 1
            i=$((i + 1))
        done
        if kill -0 "$pid" 2> /dev/null; then
            kill "$pid"
            echo timeout
        else
            echo "$i"
        fi' sh "$1"
}

result=0

load_fixture proxy

for action in stop start restart; do
    info "service okop reload, then $action"
    on_router /etc/init.d/okop reload > /dev/null 2>&1
    sleep 5

    took="$(time_init_action "$action")"
    if [ "$took" = "timeout" ]; then
        fail "service okop $action after a reload did not finish in 30s" || result=1
        # Free the lock held by the background jobs, so the rest of the suite can run
        on_router sh -c 'kill $(cat /var/run/okop_dns_guard.pid /var/run/okop_list_update.pid 2> /dev/null) 2> /dev/null' || true
    else
        pass "service okop $action after a reload finished in ${took}s"
    fi
done

on_router /etc/init.d/okop start > /dev/null 2>&1 || true
exit "$result"
