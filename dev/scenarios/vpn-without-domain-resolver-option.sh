#!/bin/sh
# shellcheck shell=dash
# A VPN section where "Domain Resolver" was never saved has no domain_resolver_enabled option. It was
# compared as a number, and every start wrote "ash: out of range" to the system log.
# Expected: okop starts without shell errors in the log, the resolver stays off.

set -eu

. "$(dirname "$0")/../lib.sh"

cleanup() {
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Unique per run, the log keeps earlier runs
MARKER="vpn-without-domain-resolver-option-$$-$(date +%s)"

log_since_restart() {
    on_router sh -c "logread | sed -n '/okop-scenario.*$MARKER/,\$p'"
}

result=0

info "VPN section without the domain resolver option"
on_router sh -c "
    cp /root/fixtures/vpn-missing.uci /etc/config/okop
    uci -q delete okop.main.domain_resolver_enabled
    uci commit okop
    logger -t okop-scenario $MARKER
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop

errors="$(log_since_restart | grep -c "ash: .*out of range" || true)"
if [ "$errors" = "0" ]; then
    pass "no shell errors in the log"
else
    fail "$errors shell error(s) in the log: $(log_since_restart | grep "ash: .*out of range" | tail -1)" || result=1
fi

if on_router jq -e '.outbounds[] | select(.tag == "main-out") | has("domain_resolver") | not' /etc/sing-box/config.json > /dev/null; then
    pass "the domain resolver is off"
else
    fail "the VPN outbound has a domain resolver" || result=1
fi

exit "$result"
