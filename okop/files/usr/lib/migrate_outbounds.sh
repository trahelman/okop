# shellcheck shell=busybox
# Moves connection settings out of sections into connections ("outbound" UCI sections).
#
# Up to 0.6 a Proxy or VPN section held its connection itself: a link, a JSON outbound, a list of links
# for Selector/URLTest or a network interface. Now a connection is a section of type "outbound" and a
# section refers to it by name (option outbound), so that one connection can serve several sections and
# connections can be grouped (fallback, urltest, selector).
#
# Uses only the uci command: it runs from uci-defaults on install and from okop on every start, which
# also converts a configuration restored from a backup or written by hand in the old format.

# The configuration as it was before the first conversion. 0.6 cannot read the new layout: going back
# means restoring this file.
MIGRATION_BACKUP="/etc/okop/okop-before-connections.backup"

# Prints a section name that is not taken yet, starting with the given one
migration_free_name() {
    local name="$1"
    local candidate="$name"
    local n=2

    while uci -q get "okop.$candidate" > /dev/null; do
        candidate="${name}_$n"
        n=$((n + 1))
    done

    echo "$candidate"
}

# Copies an option from one section to another if it is set
migration_copy_option() {
    local from="$1"
    local to="$2"
    local option="$3"
    local new_option="${4:-$option}"

    local value
    value="$(uci -q get "okop.$from.$option")" || return 0
    [ -z "$value" ] || uci set "okop.$to.$new_option=$value"
}

# Creates a connection from a single proxy link
migration_add_url_outbound() {
    local name="$1"
    local url="$2"
    local udp_over_tcp="$3"

    uci set "okop.$name=outbound" || return 1
    uci set "okop.$name.type=url"
    uci set "okop.$name.url=$url"
    [ "$udp_over_tcp" != "1" ] || uci set "okop.$name.udp_over_tcp=1"
}

# Tags of the old layout and the tags their connections get now, "old new" per line. JSON outbounds
# may refer to other outbounds by tag (detour), those references are rewritten at the end.
migration_note_tag() {
    migration_tags="$migration_tags
$1-out $2-out"
}

# Converts one section in the current shell (not in $(...): the tag notes must survive), the new
# connection's name is left in migrated_outbound
migration_convert_section() {
    local section="$1"

    local connection_type outbound
    connection_type="$(uci -q get "okop.$section.connection_type")"

    # A section saved by the LuCI of 0.6 (cached in a browser) after the conversion: it already names
    # a connection and has no connection settings of its own, only the old type
    local existing
    existing="$(uci -q get "okop.$section.outbound")"
    if [ -n "$existing" ] && [ "$(uci -q get "okop.$existing")" = "outbound" ] &&
        [ -z "$(uci -q get "okop.$section.proxy_string")$(uci -q get "okop.$section.outbound_json")" ] &&
        [ -z "$(uci -q get "okop.$section.selector_proxy_links")$(uci -q get "okop.$section.urltest_proxy_links")" ] &&
        [ -z "$(uci -q get "okop.$section.interface")" ]; then
        outbound="$existing"
    else
        outbound="$(migration_free_name "${section}_out")"
        migration_note_tag "$section" "$outbound"

        case "$connection_type" in
        proxy)
            local proxy_config_type udp_over_tcp
            proxy_config_type="$(uci -q get "okop.$section.proxy_config_type")"
            udp_over_tcp="$(uci -q get "okop.$section.enable_udp_over_tcp")"

            case "$proxy_config_type" in
            outbound)
                uci set "okop.$outbound=outbound" || return 1
                uci set "okop.$outbound.type=json"
                migration_copy_option "$section" "$outbound" "outbound_json" "json"
                ;;
            selector | urltest)
                local links link member i=1
                links="$(uci -q get "okop.$section.${proxy_config_type}_proxy_links")"

                uci set "okop.$outbound=outbound" || return 1
                uci set "okop.$outbound.type=$proxy_config_type"
                for link in $links; do
                    member="$(migration_free_name "${section}_$i")"
                    migration_add_url_outbound "$member" "$link" "$udp_over_tcp" || return 1
                    uci add_list "okop.$outbound.members=$member"
                    migration_note_tag "$section-$i" "$member"
                    i=$((i + 1))
                done

                if [ "$proxy_config_type" = "urltest" ]; then
                    migration_copy_option "$section" "$outbound" "urltest_testing_url" "check_url"
                    migration_copy_option "$section" "$outbound" "urltest_check_interval" "check_interval"
                    migration_copy_option "$section" "$outbound" "urltest_tolerance" "tolerance"
                    migration_note_tag "$section-urltest" "$outbound-urltest"
                fi
                ;;
            *)
                # The field took several lines, the first link was used and the others were kept
                # commented out with "//". They become spare connections, unused until chosen.
                local lines first spare_name n=1
                lines="$(uci -q get "okop.$section.proxy_string" |
                    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')"
                first="$(echo "$lines" | grep -v '^//' | head -n 1)"
                migration_add_url_outbound "$outbound" "$first" "$udp_over_tcp" || return 1

                echo "$lines" | sed 's|^//[[:space:]]*||' | grep -E '^[a-z0-9]+://' | grep -vxF "$first" |
                    while IFS= read -r link; do
                        spare_name="$(migration_free_name "${section}_spare_$n")"
                        migration_add_url_outbound "$spare_name" "$link" "$udp_over_tcp"
                        n=$((n + 1))
                    done
                ;;
            esac
            ;;
        vpn)
            uci set "okop.$outbound=outbound" || return 1
            uci set "okop.$outbound.type=interface"
            migration_copy_option "$section" "$outbound" "interface"
            migration_copy_option "$section" "$outbound" "domain_resolver_enabled"
            migration_copy_option "$section" "$outbound" "domain_resolver_dns_type"
            migration_copy_option "$section" "$outbound" "domain_resolver_dns_server"
            ;;
        *)
            return 1
            ;;
        esac

        # The mixed proxy sends what it receives through the connection, so it belongs to the connection
        migration_copy_option "$section" "$outbound" "mixed_proxy_enabled"
        migration_copy_option "$section" "$outbound" "mixed_proxy_port"
    fi

    # Nothing is deleted unless the connection really exists: a failed "uci set" (e.g. an invalid name)
    # would otherwise lose the link
    [ "$(uci -q get "okop.$outbound")" = "outbound" ] || return 1

    local option
    for option in proxy_config_type proxy_string outbound_json selector_proxy_links urltest_proxy_links \
        urltest_check_interval urltest_tolerance urltest_testing_url enable_udp_over_tcp interface \
        domain_resolver_enabled domain_resolver_dns_type domain_resolver_dns_server mixed_proxy_enabled \
        mixed_proxy_port; do
        uci -q delete "okop.$section.$option"
    done
    uci set "okop.$section.connection_type=outbound"
    uci set "okop.$section.outbound=$outbound"

    migrated_outbound="$outbound"
}

# Points "detour" and other tag references inside JSON connections at the renamed tags
migration_rewrite_json_tags() {
    local connection json new_json old new

    [ -n "$migration_tags" ] || return 0

    for connection in $(uci -q -X show okop | sed -n 's/^okop\.\([^.=]*\)=outbound$/\1/p'); do
        [ "$(uci -q get "okop.$connection.type")" = "json" ] || continue
        json="$(uci -q get "okop.$connection.json")"
        new_json="$json"
        while read -r old new; do
            [ -n "$old" ] || continue
            new_json="$(printf '%s' "$new_json" | sed "s/\"$old\"/\"$new\"/g")"
        done << EOF
$migration_tags
EOF
        [ "$new_json" = "$json" ] || uci set "okop.$connection.json=$new_json"
    done
}

# Returns 0 when the configuration was changed
migrate_sections_to_outbounds() {
    local section connection_type outbound migrated_outbound changed=1 migration_tags=""

    # -X: anonymous sections get their real names (cfg0a1b2c) instead of @section[0], which cannot be
    # a prefix of a new section name
    for section in $(uci -q -X show okop | sed -n 's/^okop\.\([^.=]*\)=section$/\1/p'); do
        connection_type="$(uci -q get "okop.$section.connection_type")"
        case "$connection_type" in
        proxy | vpn) ;;
        *) continue ;;
        esac

        if [ "$changed" -eq 1 ] && [ ! -f "$MIGRATION_BACKUP" ]; then
            mkdir -p "${MIGRATION_BACKUP%/*}"
            cp /etc/config/okop "$MIGRATION_BACKUP"
        fi

        if ! migration_convert_section "$section"; then
            logger -t okop "Section '$section': its connection could not be converted, the configuration is left as it was"
            uci revert okop
            return 1
        fi
        outbound="$migrated_outbound"
        logger -t okop "Section '$section': its connection was moved to the connection '$outbound'"
        changed=0

        if [ "$(uci -q get okop.settings.download_lists_via_proxy_section)" = "$section" ]; then
            uci set "okop.settings.download_lists_via_outbound=$outbound"
            uci -q delete okop.settings.download_lists_via_proxy_section
        fi
    done

    # A list download setting that still names a section: one converted earlier gives its connection,
    # a Block or Exclusion section none (the first connection is used then)
    local download_section
    download_section="$(uci -q get okop.settings.download_lists_via_proxy_section)"
    if [ -n "$download_section" ]; then
        outbound="$(uci -q get "okop.$download_section.outbound")"
        [ -z "$outbound" ] || uci set "okop.settings.download_lists_via_outbound=$outbound"
        uci -q delete okop.settings.download_lists_via_proxy_section
        changed=0
    fi

    [ "$changed" -eq 0 ] || return 1

    migration_rewrite_json_tags
    uci commit okop
}
