# Shared helpers for dev/okop-dev and dev/scenarios/*.sh
# shellcheck shell=dash

DEV_DIR="$(cd "$(dirname "$0")" && pwd)"
while [ ! -f "$DEV_DIR/compose.yml" ]; do
    [ "$DEV_DIR" != "/" ] || { echo "dev/compose.yml not found" >&2; exit 1; }
    DEV_DIR="$(dirname "$DEV_DIR")"
done

ROUTER_LAN_IP="192.168.77.1"

dc() {
    docker compose -f "$DEV_DIR/compose.yml" "$@"
}

on_router() {
    dc exec -T router "$@"
}

on_client() {
    dc exec -T client "$@"
}

info() {
    printf '\033[36m==> %s\033[0m\n' "$*"
}

pass() {
    printf '\033[32mPASS: %s\033[0m\n' "$*"
}

fail() {
    printf '\033[31mFAIL: %s\033[0m\n' "$*"
    return 1
}

wait_for() {
    local timeout="$1"
    shift
    local i=0
    while [ "$i" -lt "$timeout" ]; do
        "$@" > /dev/null 2>&1 && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

router_booted() {
    on_router test -f /tmp/devenv.ready
}

wait_boot() {
    info "Waiting for the router to boot"
    wait_for 90 router_booted || fail "router did not boot in 90s"
}

okop_enabled() {
    on_router test -e /etc/rc.d/S99okop
}

okop_started() {
    on_router test -f /var/run/okop_list_update.pid
}

# okop start is asynchronous: wait for it to finish, then give sing-box time to either settle or crash
wait_okop() {
    info "Waiting for okop to start"
    wait_for 120 okop_started || fail "okop did not start in 120s"
    sleep 15
}

reboot_router() {
    info "Rebooting the router"
    dc restart router > /dev/null
    wait_boot
    if okop_enabled; then
        wait_okop
    fi
}

# The translation is compiled from the mounted .po file, so run it again after editing translations
install_translation() {
    info "Installing the Russian translation of the LuCI app"
    # Built separately: on the first run compose would print the build log into the compiled file
    dc build -q po2lmo > /dev/null
    dc run --rm -T po2lmo 2> /dev/null |
        on_router sh -c 'cat > /tmp/okop.ru.lmo && mv /tmp/okop.ru.lmo /usr/lib/lua/luci/i18n/okop.ru.lmo && rm -f /tmp/luci-indexcache*'
}

load_fixture() {
    local name="$1"
    info "Loading fixture '$name'"
    on_router cp "/root/fixtures/$name.uci" /etc/config/okop
    on_router /etc/init.d/okop enable
    on_router /etc/init.d/okop restart
    wait_okop
}

client_resolves() {
    local domain="${1:-openwrt.org}"
    # dig prints timeouts to stdout too, so look for an actual address
    on_client dig +short +time=2 +tries=1 "@$ROUTER_LAN_IP" "$domain" A | grep -qE '^[0-9]+(\.[0-9]+){3}$'
}

# Domains from the routed lists resolve to fake IPs (198.18.0.0/15) only when DNS goes through sing-box
client_gets_fakeip() {
    local domain="${1:-youtube.com}"
    on_client dig +short +time=2 +tries=1 "@$ROUTER_LAN_IP" "$domain" A | grep -qE '^198\.1[89]\.'
}

# sing-box answers the service domain with a fake IP by itself, even before any list is downloaded
singbox_answers_fakeip() {
    on_router dig +short +time=2 +tries=1 @127.0.0.42 fakeip.podkop.fyi A | grep -qE '^198\.1[89]\.'
}

client_fetches() {
    local url="${1:-https://openwrt.org}"
    on_client curl -sS -o /dev/null -m 10 "$url"
}

# The service answers "fakeip": true only when it sees the connection arrive through sing-box
client_confirms_fakeip() {
    on_client curl -s -m 10 https://fakeip.podkop.fyi/check | grep -q '"fakeip": true'
}

# dnsmasq actually forwards to sing-box. "okop started" does not imply this: reload leaves dnsmasq
# on the upstream servers, and then nothing from the lists is routed
dnsmasq_uses_singbox() {
    on_router uci -q get dhcp.@dnsmasq[0].server | grep -q '127\.0\.0\.42'
}

dns_guard_running() {
    on_router test -f /var/run/okop_dns_guard.pid
}

# Prints the sing-box outbound okop builds for a proxy link, without restarting okop
outbound_for_link() {
    on_router sh -c '
        . /usr/lib/okop/constants.sh
        . /usr/lib/okop/logging.sh
        . /usr/lib/okop/sing_box_config_facade.sh
        sing_box_cf_add_proxy_outbound "{\"outbounds\":[]}" main "$1" 0 | jq -c ".outbounds[0]"' sh "$1"
}

singbox_running() {
    on_router pidof sing-box > /dev/null
}

# Running with the same PID for 10 seconds, i.e. not in a crash loop
singbox_stable() {
    local pid_before pid_after
    pid_before="$(on_router pidof sing-box)" || return 1
    sleep 10
    pid_after="$(on_router pidof sing-box)" || return 1
    [ "$pid_before" = "$pid_after" ]
}
