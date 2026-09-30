#!/bin/sh
# shellcheck shell=dash
# okop start/restart/reload run through a pipe (like "ssh router okop reload" without a terminal)
# while lists cannot be downloaded. Background jobs must not keep the pipe open.
# Expected: every command returns within 30 seconds.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    dc start proxy > /dev/null
}
trap cleanup EXIT

# Prints the seconds the command took, or "timeout" after 30 seconds
time_through_pipe() {
    on_router sh -c '
        ( okop "$1" 2>&1 | cat > /dev/null ) &
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

dc start proxy > /dev/null
load_fixture proxy

info "Stopping the proxy, lists cannot be downloaded"
dc stop proxy > /dev/null

for command in reload restart; do
    took="$(time_through_pipe "$command")"
    if [ "$took" = "timeout" ]; then
        fail "okop $command through a pipe did not return in 30s" || result=1
    else
        pass "okop $command through a pipe returned in ${took}s"
    fi
done

exit "$result"
