#!/bin/sh
# shellcheck shell=dash
# Proxy links in shapes common clients produce, each of which used to give an outbound that looked
# fine and never connected:
#   - trojan without security= got no TLS;
#   - ss userinfo in base64url (SIP002) lost everything after the first "-" or "_" of the password;
#   - ss plugin= (obfs-local, v2ray-plugin) was dropped.
# Expected: the generated outbound matches the link.

set -eu

. "$(dirname "$0")/../lib.sh"

result=0

# Checks a jq expression against the outbound built for a link
expect() {
    local description="$1" link="$2" filter="$3"
    if outbound_for_link "$link" | jq -e "$filter" > /dev/null 2>&1; then
        pass "$description"
    else
        fail "$description: got $(outbound_for_link "$link")" || result=1
    fi
}

expect "trojan without security= uses TLS" \
    'trojan://pass@example.com:443?sni=example.com#t' \
    '.tls.enabled == true and .tls.server_name == "example.com"'

expect "trojan with security=none stays without TLS" \
    'trojan://pass@example.com:443?security=none#t' \
    '.tls == null'

expect "ss base64url userinfo without padding keeps the whole password" \
    'ss://YWVzLTI1Ni1nY206eHg_P3l5Pj56eg@1.2.3.4:8388#s' \
    '.method == "aes-256-gcm" and .password == "xx??yy>>zz"'

expect "ss obfs-local plugin and its options are passed" \
    'ss://YWVzLTEyOC1nY206eHg@1.2.3.4:8388/?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com#s' \
    '.plugin == "obfs-local" and .plugin_opts == "obfs=http;obfs-host=example.com"'

expect "ss simple-obfs is mapped to obfs-local" \
    'ss://YWVzLTEyOC1nY206eHg@1.2.3.4:8388?plugin=simple-obfs%3Bobfs%3Dtls#s' \
    '.plugin == "obfs-local" and .plugin_opts == "obfs=tls"'

exit "$result"
