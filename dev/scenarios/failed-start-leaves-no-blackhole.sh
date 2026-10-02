#!/bin/sh
# shellcheck shell=dash
# A configuration that sing-box rejects or whose generation aborts, or a config_path whose directory
# does not exist. The start aborts, but the nft table and the ip rule were already installed, so
# traffic to okop_subnets and to the fake-IP range kept being tproxy'd to a sing-box that is not
# listening -- blackholed -- while domains resolved to real addresses and left in the clear.
# Expected: a failed start removes the interception and gives dnsmasq back, i.e. okop is just off.

set -eu

. "$(dirname "$0")/../lib.sh"

nft_table_present() {
    on_router nft list table inet OkopTable > /dev/null 2>&1
}

ip_rule_present() {
    on_router sh -c 'ip rule list | grep -q okop'
}

show_state() {
    on_router sh -c 'logread -e okop | grep -iE "fatal|rollback|interception" | tail -4; uci show dhcp.@dnsmasq[0].server'
}

MISSING_DIR=/etc/sing-box/missing-dir

cleanup() {
    on_router rm -rf "$MISSING_DIR" > /dev/null 2>&1 || true
    load_fixture proxy > /dev/null 2>&1 || true
}

trap cleanup EXIT

result=0

check_clean_after_failure() {
    local what="$1"

    if nft_table_present; then
        fail "$what: the nft table is left behind, traffic is blackholed" || return 1
    else
        pass "$what: the nft table is removed"
    fi

    if ip_rule_present; then
        fail "$what: the ip rule is left behind" || return 1
    else
        pass "$what: the ip rule is removed"
    fi

    if dnsmasq_uses_singbox; then
        fail "$what: dnsmasq still forwards to a sing-box that is not running" || return 1
    else
        pass "$what: dnsmasq does not forward to sing-box"
    fi

    if wait_for 15 client_resolves; then
        pass "$what: client DNS works"
    else
        fail "$what: client has no DNS" || return 1
    fi
}

# A port value sing-box cannot parse. The LuCI field now refuses it, but a config written before the
# validator existed, or edited over SSH, still reaches the backend.
load_fixture proxy
info "Starting with a mixed proxy port sing-box cannot parse"
on_router sh -c "
    uci set okop.main.mixed_proxy_enabled=1
    uci set okop.main.mixed_proxy_port=8080x
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 20

if on_router pidof sing-box > /dev/null; then
    fail "baseline: sing-box is running, the config was not rejected" || result=1
    show_state
else
    check_clean_after_failure "invalid mixed proxy port" || result=1
fi

# A second proxy section without a link. check_requirements is satisfied by any section with an
# outbound, so the start gets past the nft rules and aborts while generating the outbounds.
load_fixture proxy
info "Starting with a second proxy section without a proxy link"
on_router sh -c "
    uci set okop.broken=section
    uci set okop.broken.connection_type=proxy
    uci set okop.broken.proxy_config_type=url
    uci add_list okop.broken.user_domains=example.org
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
sleep 20

if on_router pidof sing-box > /dev/null; then
    fail "baseline: sing-box is running with a section without a proxy link" || result=1
    show_state
else
    check_clean_after_failure "section without a proxy link" || result=1
fi

# A config_path whose parent directory does not exist
load_fixture proxy
on_router rm -rf "$MISSING_DIR"
info "Starting with a config_path in a directory that does not exist"
on_router sh -c "
    uci set okop.settings.config_path=$MISSING_DIR/config.json
    uci commit okop
    /etc/init.d/okop restart" > /dev/null 2>&1
wait_for 60 singbox_running || true
sleep 10

# pidof alone passes for a sing-box crash-looping on a config file that was never written
if on_router test -s "$MISSING_DIR/config.json" && singbox_stable; then
    pass "a missing config directory is created and sing-box starts"
else
    check_clean_after_failure "unwritable config path" || result=1
fi

exit "$result"
