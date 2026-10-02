#!/bin/sh
# shellcheck shell=dash
# Lists that sing-box does not read as rule set files -- community subnet lists, remote plain-text lists
# and the subnets of remote .srs lists -- lived only in nft sets and /tmp and were filled only by a
# successful download. After a reboot with WAN or the proxy coming up late they stayed empty until the
# next cron run, up to a day.
# Expected: after a reboot without access to GitHub they are applied from the stored copies right away,
# and the start-time update keeps retrying instead of giving up.

set -eu

. "$(dirname "$0")/../lib.sh"

PLAIN_LIST='https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/hdrezka.lst'
SRS_SUBNETS='https://github.com/itdoginfo/allow-domains/releases/latest/download/discord.srs'

block_github() {
    on_router sh -c "uci add_list dhcp.@dnsmasq[0].address='/github.com/0.0.0.0'; uci add_list dhcp.@dnsmasq[0].address='/githubusercontent.com/0.0.0.0'; uci commit dhcp; /etc/init.d/dnsmasq reload"
}

unblock_github() {
    on_router sh -c "uci -q del_list dhcp.@dnsmasq[0].address='/github.com/0.0.0.0'; uci -q del_list dhcp.@dnsmasq[0].address='/githubusercontent.com/0.0.0.0'; uci commit dhcp; /etc/init.d/dnsmasq reload"
}

set_size() {
    on_router sh -c "nft list set inet OkopTable $1 2> /dev/null | tr ',' '\n' | grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'" || echo 0
}

lists_ready() {
    [ "$(set_size okop_discord_subnets)" -gt 0 ] && [ "$(set_size okop_subnets)" -gt 0 ] && client_gets_fakeip rezka.ag
}

cleanup() {
    unblock_github > /dev/null 2>&1 || true
    dc start proxy > /dev/null
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

result=0

dc start proxy > /dev/null
load_fixture proxy
on_router sh -c "uci add_list okop.main.remote_domain_lists='$PLAIN_LIST'; uci add_list okop.main.remote_subnet_lists='$SRS_SUBNETS'; uci commit okop; /etc/init.d/okop restart" > /dev/null 2>&1
sleep 2
wait_okop
wait_for 120 lists_ready || fail "baseline: the lists were not downloaded"
info "baseline: discord set $(set_size okop_discord_subnets), common set $(set_size okop_subnets) entries"

info "Blocking GitHub, stopping the proxy and rebooting"
block_github
dc stop proxy > /dev/null
reboot_router

if [ "$(set_size okop_discord_subnets)" -gt 0 ]; then
    pass "community subnet list is applied from the stored copy"
else
    fail "community subnet list is empty after the reboot" || result=1
fi

if [ "$(set_size okop_subnets)" -gt 0 ]; then
    pass "subnets of the remote .srs list are applied from the stored copy"
else
    fail "subnets of the remote .srs list are empty after the reboot" || result=1
fi

if wait_for 15 client_gets_fakeip rezka.ag; then
    pass "remote plain-text domain list is applied from the stored copy"
else
    fail "remote plain-text domain list is empty after the reboot" || result=1
fi

if wait_for 180 on_router sh -c 'logread -e okop | grep -q "retrying in"'; then
    pass "the start-time lists update retries while GitHub is unreachable"
else
    fail "the start-time lists update gave up" || result=1
fi

exit "$result"
