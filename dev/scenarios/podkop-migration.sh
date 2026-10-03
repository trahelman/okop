#!/bin/sh
# shellcheck shell=dash
# okop's uci-defaults script migrates /etc/config/podkop on install, and runs again on every upgrade.
#   - A migrated config must not be copied over okop's again on the next upgrade.
#   - Podkop before 0.7 has no "settings" section: the flag was never stored and every upgrade
#     overwrote okop's config with a layout okop cannot use.
# Expected: a current Podkop config is migrated once, with its connections moved out of the sections like
# any old okop config, an old one is left alone, okop's config is kept.

set -eu

. "$(dirname "$0")/../lib.sh"

MIGRATE=/etc/uci-defaults/50_okop_migrate_podkop
CONVERT=/etc/uci-defaults/60_okop_outbounds

run_migration() {
    on_router sh -c "sh /opt/okop$MIGRATE; sh /opt/okop$CONVERT"
}

cleanup() {
    on_router sh -c 'rm -f /etc/config/podkop /etc/podkop.migrated' || true
    load_fixture proxy > /dev/null 2>&1 || true
}
trap cleanup EXIT

result=0

load_fixture proxy
on_router /etc/init.d/okop stop > /dev/null 2>&1

info "Migrating a Podkop 0.7+ config"
on_router sh -c "
    rm -f /etc/podkop.migrated
    sed -e \"s/okop/podkop/g\" -e \"s/#dev-proxy/#from-podkop/\" /root/fixtures/legacy-sections.uci > /etc/config/podkop
    uci -q delete okop.settings.migrated_from_podkop; uci commit okop"
run_migration
if [ "$(on_router uci -q get okop.main.outbound)" = "main_out" ] &&
    [ "$(on_router uci -q get okop.main_out.url)" = "$(on_router sh -c "sed -n \"s/.*proxy_string '\\(.*\\)'/\\1/p\" /etc/podkop.migrated")" ] &&
    on_router uci -q get okop.main_out.url | grep -q from-podkop; then
    pass "the Podkop config is migrated"
else
    fail "the Podkop config is not migrated" || result=1
fi

info "Running the migration again, as an okop upgrade does"
on_router sh -c "uci set okop.main_out.url='ss://YWVzLTEyOC1nY206b2tvcC1kZXY=@172.31.77.3:8388#edited-in-okop'; uci commit okop"
run_migration
if on_router uci -q get okop.main_out.url | grep -q edited-in-okop; then
    pass "an upgrade keeps the okop config"
else
    fail "an upgrade copied the Podkop config over the okop one again" || result=1
fi

info "A config from Podkop before 0.7"
on_router sh -c "
    rm -f /etc/podkop.migrated
    printf \"config main 'main'\\n\\toption mode 'proxy'\\n\\toption proxy_string 'ss://old'\\n\" > /etc/config/podkop"
before="$(on_router md5sum /etc/config/okop)"
run_migration
run_migration
if [ "$(on_router md5sum /etc/config/okop)" = "$before" ] && ! on_router test -f /etc/config/podkop; then
    pass "an old Podkop config is left alone and moved away"
else
    fail "an old Podkop config changed the okop config" || result=1
fi

on_router /etc/init.d/okop start > /dev/null 2>&1
exit "$result"
