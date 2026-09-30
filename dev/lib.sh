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

client_fetches() {
    local url="${1:-https://openwrt.org}"
    on_client curl -sS -o /dev/null -m 10 "$url"
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
