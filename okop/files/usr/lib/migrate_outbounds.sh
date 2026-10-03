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
    [ -n "$value" ] && uci set "okop.$to.$new_option=$value"
}

# Creates a connection from a single proxy link, returns its name
migration_add_url_outbound() {
    local name="$1"
    local url="$2"
    local udp_over_tcp="$3"

    uci set "okop.$name=outbound"
    uci set "okop.$name.type=url"
    uci set "okop.$name.url=$url"
    [ "$udp_over_tcp" = "1" ] && uci set "okop.$name.udp_over_tcp=1"
}

migration_convert_section() {
    local section="$1"

    local connection_type outbound
    connection_type="$(uci -q get "okop.$section.connection_type")"
    outbound="$(migration_free_name "${section}_out")"

    case "$connection_type" in
    proxy)
        local proxy_config_type udp_over_tcp
        proxy_config_type="$(uci -q get "okop.$section.proxy_config_type")"
        udp_over_tcp="$(uci -q get "okop.$section.enable_udp_over_tcp")"

        case "$proxy_config_type" in
        outbound)
            uci set "okop.$outbound=outbound"
            uci set "okop.$outbound.type=json"
            migration_copy_option "$section" "$outbound" "outbound_json" "json"
            ;;
        selector | urltest)
            local links link member i=1
            links="$(uci -q get "okop.$section.${proxy_config_type}_proxy_links")"

            uci set "okop.$outbound=outbound"
            uci set "okop.$outbound.type=$proxy_config_type"
            for link in $links; do
                member="$(migration_free_name "${section}_$i")"
                migration_add_url_outbound "$member" "$link" "$udp_over_tcp"
                uci add_list "okop.$outbound.members=$member"
                i=$((i + 1))
            done

            if [ "$proxy_config_type" = "urltest" ]; then
                migration_copy_option "$section" "$outbound" "urltest_testing_url" "check_url"
                migration_copy_option "$section" "$outbound" "urltest_check_interval" "check_interval"
                migration_copy_option "$section" "$outbound" "urltest_tolerance" "tolerance"
            fi
            ;;
        *)
            # The field took several lines with "//" comments, only the first link was used
            local url
            url="$(uci -q get "okop.$section.proxy_string" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
                grep -v '^//' | grep -v '^$' | head -n 1)"
            migration_add_url_outbound "$outbound" "$url" "$udp_over_tcp"
            ;;
        esac
        ;;
    vpn)
        uci set "okop.$outbound=outbound"
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

    local option
    for option in proxy_config_type proxy_string outbound_json selector_proxy_links urltest_proxy_links \
        urltest_check_interval urltest_tolerance urltest_testing_url enable_udp_over_tcp interface \
        domain_resolver_enabled domain_resolver_dns_type domain_resolver_dns_server mixed_proxy_enabled \
        mixed_proxy_port; do
        uci -q delete "okop.$section.$option"
    done
    uci set "okop.$section.connection_type=outbound"
    uci set "okop.$section.outbound=$outbound"

    if [ "$(uci -q get okop.settings.download_lists_via_proxy_section)" = "$section" ]; then
        uci set "okop.settings.download_lists_via_outbound=$outbound"
        uci -q delete okop.settings.download_lists_via_proxy_section
    fi

    echo "$outbound"
}

# Returns 0 when the configuration was changed
migrate_sections_to_outbounds() {
    local section connection_type outbound changed=1

    for section in $(uci -q show okop | sed -n 's/^okop\.\([^.=]*\)=section$/\1/p'); do
        connection_type="$(uci -q get "okop.$section.connection_type")"
        case "$connection_type" in
        proxy | vpn) ;;
        *) continue ;;
        esac

        outbound="$(migration_convert_section "$section")" || continue
        logger -t okop "Section '$section': its connection was moved to the connection '$outbound'"
        changed=0
    done

    # A list download section that is not a Proxy/VPN section any more would point nowhere
    if uci -q get okop.settings.download_lists_via_proxy_section > /dev/null; then
        uci -q delete okop.settings.download_lists_via_proxy_section
        changed=0
    fi

    [ "$changed" -eq 0 ] && uci commit okop
    return "$changed"
}
