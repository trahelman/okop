#!/bin/sh
# shellcheck shell=dash
# A remote subnet list in sing-box rule-set format where not every rule carries ip_cidr -- the shape
# of the community lists this project ships. Extraction used "jq -r '.rules[].ip_cidr[]'", which dies
# on the first rule without ip_cidr, so no subnet at all reached nftables and that traffic left in the
# clear with nothing in the log.
# Expected: the ip_cidr entries end up in the okop_subnets set.

set -eu

. "$(dirname "$0")/../lib.sh"

LIST_URL="http://127.0.0.1/mixed-subnets.json"

# A domain rule before the subnet rule, exactly like the shipped discord rule set
publish_list() {
    on_router sh -c "cat > /www/mixed-subnets.json" << 'EOF'
{
  "version": 3,
  "rules": [
    { "domain_suffix": ["mixed-list.invalid"] },
    { "ip_cidr": ["100.64.77.0/24", "100.64.99.0/24"] }
  ]
}
EOF
}

subnet_in_set() {
    on_router nft list set inet OkopTable okop_subnets | grep -q "$1"
}

cleanup() {
    on_router rm -f /www/mixed-subnets.json
}

trap cleanup EXIT

result=0

load_fixture proxy
publish_list

info "Adding the list and restarting okop"
on_router sh -c "
    uci set okop.settings.download_lists_via_proxy=0
    uci add_list okop.main.remote_subnet_lists='$LIST_URL'
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
wait_okop

if wait_for 90 subnet_in_set "100.64.77.0/24"; then
    pass "a subnet from a rule set with mixed rules reaches nftables"
else
    fail "no subnet from a rule set with mixed rules reached nftables" || result=1
    on_router sh -c 'logread -e okop | grep -iE "ip_cidr|subnet" | tail -5'
fi

if subnet_in_set "100.64.99.0/24"; then
    pass "every subnet of the rule is imported"
else
    fail "only part of the rule was imported" || result=1
fi

exit "$result"
