#!/bin/sh
# shellcheck shell=dash
# Credentials from a proxy link must reach the sing-box config byte for byte. The whole URL used to be
# percent-decoded before it was split, which turned every "+" in a password into a space and let a
# %40 in a password become an "@" and move the host boundary. The config stayed valid JSON and
# sing-box started, so the only symptom was that the proxy never authenticated.
# Expected: the password, the server and the port in the generated config match the link.

set -eu

. "$(dirname "$0")/../lib.sh"

CONFIG=/etc/sing-box/config.json

outbound_field() {
    on_router jq -r "[.outbounds[] | select(.type == \"$1\")][0].$2" "$CONFIG"
}

apply_proxy_string() {
    on_router sh -c "
        uci set okop.main.proxy_config_type=url
        uci set okop.main.proxy_string='$1'
        uci commit okop
        /etc/init.d/okop restart" > /dev/null 2>&1
    wait_okop
}

check_field() {
    local what="$1" type="$2" field="$3" expected="$4" actual
    actual="$(outbound_field "$type" "$field")"

    if [ "$actual" = "$expected" ]; then
        pass "$what"
    else
        fail "$what: expected [$expected], got [$actual]" || return 1
    fi
}

result=0

load_fixture proxy

# "+" is a literal character in a base64 password; roughly 1 in 64 base64 characters is one
info "A shadowsocks link whose password contains +"
apply_proxy_string 'ss://2022-blake3-aes-256-gcm:dmCly/Zh15Ww9+s+GFXiFTIkpw7c/qCISaBrai7WhhY=@172.31.77.3:8388#plus'
check_field "the + in a shadowsocks password is preserved" shadowsocks password \
    'dmCly/Zh15Ww9+s+GFXiFTIkpw7c/qCISaBrai7WhhY=' || result=1
check_field "the shadowsocks method is preserved" shadowsocks method '2022-blake3-aes-256-gcm' || result=1

# %40 must decode to "@" only after the userinfo and the host have been split apart
info "A socks5 link whose password is percent-encoded"
apply_proxy_string 'socks5://user:p%40ss@172.31.77.3:1080#enc'
check_field "a percent-encoded socks5 password is decoded" socks password 'p@ss' || result=1
check_field "the socks5 username is kept" socks username 'user' || result=1
check_field "the socks5 host is not taken from the password" socks server '172.31.77.3' || result=1
check_field "the socks5 port is not taken from the password" socks server_port '1080' || result=1

# Without a colon there is no password at all, and the username must not be reused as one
info "A socks5 link with a username and no password"
apply_proxy_string 'socks5://justuser@172.31.77.3:1080#nopass'
check_field "the socks5 username is kept without a password" socks username 'justuser' || result=1
if [ "$(outbound_field socks password)" = "justuser" ]; then
    fail "the socks5 username was reused as the password" || result=1
else
    pass "the socks5 username is not reused as the password"
fi

exit "$result"
