#!/bin/sh
# shellcheck shell=dash
# At start okop retries the lists update until the network is ready. An update started from LuCI while
# the retry loop sleeps held the lock when the loop woke up; the loop took "already being updated" for
# success and stopped, so after a failed button update nothing retried until cron, a day later.
# Expected: the loop waits for the other update and keeps retrying while the network is not ready.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    dc start proxy > /dev/null 2>&1 || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

update_state_is() {
    [ "$(on_router /usr/bin/okop list_update_status | jq -r .state)" = "$1" ]
}

update_finished() {
    ! update_state_is running
}

retry_loop_sleeping() {
    on_router logread -e okop | grep -q "Network is not ready for the lists update, retrying"
}

result=0

load_fixture proxy

info "Stopping the proxy the lists are downloaded through and restarting okop"
dc stop proxy > /dev/null
on_router /etc/init.d/okop restart > /dev/null 2>&1
wait_okop

# The first attempt gives up on GitHub after about two minutes, then the loop sleeps for a minute
wait_for 240 retry_loop_sleeping || fail "the update at start did not fail over to retrying" || result=1

info "Pressing the button while the retry loop sleeps"
response="$(on_router /usr/bin/okop list_update_start)"
[ "$(echo "$response" | jq -r .started)" = 1 ] || fail "the button did not start an update: $response" || result=1

# The loop wakes up while the button update still checks GitHub, which then fails as well
wait_for 240 update_finished || true
if update_state_is network; then
    pass "the button update without network ends as such"
else
    fail "unexpected status of the button update: $(on_router /usr/bin/okop list_update_status)" || result=1
fi

info "Bringing the proxy back"
dc start proxy > /dev/null

# The next retry of the start job, two minutes later, updates the lists without anyone pressing anything
if wait_for 300 update_state_is ok; then
    pass "the retry loop at start keeps going after an update from LuCI"
else
    fail "the lists were not updated after the network came back: $(on_router /usr/bin/okop list_update_status)" || result=1
    on_router logread -e okop | grep -E "update|retry|already" | tail -8
fi

exit "$result"
