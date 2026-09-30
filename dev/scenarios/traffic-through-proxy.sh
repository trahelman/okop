#!/bin/sh
# shellcheck shell=dash
# Real traffic, not only DNS: a domain from the lists gets a fake IP, the connection is intercepted by tproxy
# and sent by sing-box to the proxy by name.
# Expected: the client fetches the site, the proxy server receives the connection for that domain.

set -eu

. "$(dirname "$0")/../lib.sh"

result=0

dc start proxy > /dev/null
load_fixture proxy

wait_for 15 client_gets_fakeip example.com || fail "baseline: example.com does not get a fake IP"

if client_fetches https://example.com; then
    pass "client fetches https://example.com through the fake IP"
else
    fail "client cannot fetch https://example.com through the fake IP" || result=1
fi

if dc logs proxy --since 1m 2> /dev/null | grep -q "inbound connection to example.com:443"; then
    pass "the connection went through the proxy by domain name"
else
    fail "the proxy did not receive the connection to example.com" || result=1
fi

if on_client curl -s -m 10 https://fakeip.podkop.fyi/check | grep -q '"fakeip": true'; then
    pass "fakeip.podkop.fyi/check confirms FakeIP"
else
    fail "fakeip.podkop.fyi/check does not confirm FakeIP" || result=1
fi

exit "$result"
