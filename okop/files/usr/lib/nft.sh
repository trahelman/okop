# shellcheck shell=busybox
# Create an nftables table in the inet family
nft_create_table() {
    local name="$1"

    nft add table inet "$name"
}

# Create a set within a table for storing IPv4 addresses
nft_create_ipv4_set() {
    local table="$1"
    local name="$2"

    nft add set inet "$table" "$name" '{ type ipv4_addr; flags interval; auto-merge; }'
}

nft_create_ifname_set() {
    local table="$1"
    local name="$2"

    nft add set inet "$table" "$name" '{ type ifname; flags interval; }'
}

# Add one or more elements to a set
nft_add_set_elements() {
    local table="$1"
    local set="$2"
    local elements="$3"

    nft add element inet "$table" "$set" "{ $elements }"
}

# Adds the valid IPv4 addresses and subnets of a plain list file to an nft set, in chunks that stay under
# the argument size limit
nft_add_set_elements_from_file_chunked() {
    local filepath="$1"
    local nft_table_name="$2"
    local nft_set_name="$3"
    local chunk_size="${4:-5000}"

    local normalized chunk
    normalized="$(mktemp)"
    normalize_plain_list "$filepath" "$normalized" "subnets"
    log "Adding $(wc -l < "$normalized") elements to nft set $nft_set_name" "debug"

    awk -v size="$chunk_size" '
        { printf "%s%s", ((NR - 1) % size == 0) ? "" : ",", $0 }
        NR % size == 0 { print "" }
        END { if (NR % size != 0) print "" }
    ' "$normalized" | while IFS= read -r chunk; do
        [ -n "$chunk" ] && nft_add_set_elements "$nft_table_name" "$nft_set_name" "$chunk"
    done

    rm -f "$normalized"
}
