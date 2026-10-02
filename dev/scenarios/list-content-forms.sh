#!/bin/sh
# shellcheck shell=dash
# Lists are written by hand: "Wikipedia.org" with capitals, a link copied from the browser, a local list
# file without a newline at the end, a user subnet list of a few thousand entries. The capitals and the
# link were dropped as invalid, the last line of the file was lost, and a user list over 128 KB was
# silently left out because it was passed as one argument.
# Expected: all of them are routed.

set -eu

. "$(dirname "$0")/../lib.sh"

LOCAL_LIST=/etc/okop/test-local-domains.lst
# The last entry of the large user subnet list, outside of every other entry
MARKER_SUBNET=198.51.100.7

cleanup() {
    on_router rm -f "$LOCAL_LIST" || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

subnet_routed() {
    on_router nft get element inet OkopTable okop_subnets "{ $MARKER_SUBNET }" > /dev/null 2>&1
}

result=0

load_fixture proxy
info "Setting user domains, a local list without a final newline and a large user subnet list"
on_router sh -c "
    printf 'speedtest.net' > $LOCAL_LIST
    uci -q delete okop.main.user_domains
    uci add_list okop.main.user_domains='Wikipedia.ORG'
    uci add_list okop.main.user_domains='https://www.kernel.org/pub/linux'
    uci add_list okop.main.local_domain_lists='$LOCAL_LIST'
    uci set okop.main.user_subnet_list_type='text'
    uci commit okop
    # Over 128 KB: too large for a single command line argument, so appended to the file directly
    {
        printf \"\toption user_subnets_text '\"
        awk 'BEGIN { for (i = 0; i < 16384; i++) printf \"100.%d.%d.0/24\\n\", 64 + int(i / 256), i % 256 }'
        printf \"$MARKER_SUBNET'\\n\"
    } >> /etc/config/okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop

if [ "$(on_router sh -c 'wc -c < /etc/config/okop')" -lt 131072 ]; then
    fail "the user subnet list was not written to the configuration" || result=1
fi

for domain in wikipedia.org www.kernel.org speedtest.net; do
    if wait_for 30 client_gets_fakeip "$domain"; then
        pass "$domain is routed"
    else
        fail "$domain is not routed" || result=1
    fi
done

if subnet_routed; then
    pass "the large user subnet list is routed"
else
    fail "$MARKER_SUBNET from the large user subnet list is not in the nft set" || result=1
fi

exit "$result"
