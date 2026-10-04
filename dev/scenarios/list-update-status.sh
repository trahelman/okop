#!/bin/sh
# shellcheck shell=dash
# LuCI starts a lists update with a button and shows how it ended, and the dashboard shows the result of
# the last update, including the ones started by cron and at start. An update takes longer than rpcd
# lets a command run, so it is started in the background and its status is read separately.
# Expected: list_update_start returns at once, list_update_status reports running, then the outcome
# with the URLs that failed.

set -eu

. "$(dirname "$0")/../lib.sh"

MISSING_LIST="https://raw.githubusercontent.com/trahelman/okop/main/dev/does-not-exist.lst"

cleanup() {
    dc start proxy > /dev/null 2>&1 || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

update_status() {
    on_router /usr/bin/okop list_update_status
}

update_field() {
    update_status | jq -r ".$1"
}

update_state_is() {
    [ "$(update_field state)" = "$1" ]
}

update_finished() {
    ! update_state_is running
}

start_update() {
    on_router /usr/bin/okop list_update_start
}

started_by_button() {
    [ "$(echo "$1" | jq -r .started)" = 1 ]
}

update_started_after() {
    [ "$(update_field started)" -ge "$1" ]
}

no_update_process() {
    ! on_router pgrep -f "okop list_update" > /dev/null
}

result=0

dc start proxy > /dev/null
restarted_at="$(on_router date +%s)"
load_fixture proxy

if wait_for 120 update_state_is ok && [ "$(update_field failed)" = "[]" ] && update_started_after "$restarted_at"; then
    pass "the update at start records its result"
else
    fail "unexpected status after start: $(update_status)" || result=1
fi

info "Starting an update the way the LuCI button does"
before="$(on_router date +%s)"
response="$(start_update)"
if [ "$(echo "$response" | jq -r .started)" = 1 ] && update_state_is running; then
    pass "the update starts in the background and is reported as running"
else
    fail "unexpected start: $response, status $(update_status)" || result=1
fi

response="$(start_update)"
if [ "$(echo "$response" | jq -r .reason)" = "already_running" ]; then
    pass "a second press does not start another update"
else
    fail "a second update was started: $response" || result=1
fi

if wait_for 120 update_finished && update_state_is ok && [ "$(update_field started)" -ge "$before" ]; then
    pass "the update ends as successful"
else
    fail "unexpected status after the update: $(update_status)" || result=1
fi

info "Adding a list that does not exist"
on_router sh -c "
    uci add_list okop.main.remote_domain_lists='$MISSING_LIST'
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
wait_okop
wait_for 120 update_finished || fail "the update at restart did not finish: $(update_status)" || result=1
pressed_at="$(on_router date +%s)"
response="$(start_update)"

if started_by_button "$response" && wait_for 120 update_finished && update_state_is partial &&
    update_started_after "$pressed_at" &&
    update_status | jq -e --arg url "$MISSING_LIST" '.failed == [$url]' > /dev/null; then
    pass "a list that failed is named in the status"
else
    fail "unexpected status with a missing list: $(update_status)" || result=1
fi

info "Stopping the proxy the lists are downloaded through"
dc stop proxy > /dev/null
response="$(start_update)"

if started_by_button "$response" && wait_for 240 update_finished && update_state_is network && [ "$(update_field reason)" = "github" ]; then
    pass "an update without access to GitHub is reported as such"
else
    fail "unexpected status without the proxy: $(update_status)" || result=1
fi
dc start proxy > /dev/null

info "Stopping okop during an update"
response="$(start_update)"
started_by_button "$response" || fail "the update was not started: $response" || result=1
on_router /etc/init.d/okop stop > /dev/null 2>&1

# The update must really be gone, not just reported so: a survivor would overwrite the status later
if wait_for 30 update_state_is interrupted && no_update_process && sleep 20 &&
    update_state_is interrupted && no_update_process; then
    pass "an update killed by stop is reported as interrupted"
else
    fail "unexpected status after stop: $(update_status)" || result=1
fi

response="$(start_update)"
if [ "$(echo "$response" | jq -r .reason)" = "not_running" ]; then
    pass "no update is started while okop is stopped"
else
    fail "an update was started with okop stopped: $response" || result=1
fi

exit "$result"
