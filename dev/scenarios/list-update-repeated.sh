#!/bin/sh
# shellcheck shell=dash
# The cron lists update runs over and over while okop runs, and may overlap with the one started with okop.
#   - The discord rule was added to the nft chain again on every update.
#   - Two updates wrote the same files at the same time.
# Expected: repeated updates leave one discord rule, and an update started while another runs does not run.

set -eu

. "$(dirname "$0")/../lib.sh"

discord_rules() {
    on_router sh -c 'nft list chain inet OkopTable mangle | grep -c okop_discord_subnets' || echo 0
}

result=0

load_fixture proxy
wait_for 120 on_router sh -c '! test -d /var/lock/okop_list_update' || true

info "Running the lists update three times"
for _ in 1 2 3; do
    on_router okop list_update > /dev/null 2>&1 || true
done

if [ "$(discord_rules)" = "1" ]; then
    pass "the discord rule is in the chain once"
else
    fail "the discord rule is in the chain $(discord_rules) times" || result=1
fi

info "Starting two lists updates at once"
on_router sh -c 'okop list_update > /dev/null 2>&1 & sleep 1; okop list_update > /dev/null 2>&1; wait'
if on_router sh -c 'logread -e okop | tail -50 | grep -q "already being updated"'; then
    pass "a second update does not run while the first one does"
else
    fail "two updates ran at the same time" || result=1
fi

exit "$result"
