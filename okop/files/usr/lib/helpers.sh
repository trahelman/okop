# shellcheck shell=busybox
# OpenWrt BusyBox ash supports [[ =~ ]], glob matching in [[ ]], $RANDOM and $'..'
# shellcheck disable=SC3015,SC2330,SC3028,SC3003
# Check if string is valid IPv4
is_ipv4() {
    local ip="$1"
    local regex="^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$"
    [[ "$ip" =~ $regex ]]
}

# Check if string is valid IPv4 with CIDR mask
is_ipv4_cidr() {
    local ip="$1"
    local regex="^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}(\/(3[0-2]|2[0-9]|1[0-9]|[0-9]))$"
    [[ "$ip" =~ $regex ]]
}

is_ipv4_ip_or_ipv4_cidr() {
    is_ipv4 "$1" || is_ipv4_cidr "$1"
}

is_domain() {
    local str="$1"
    local regex='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$'

    [[ "$str" =~ $regex ]]
}

is_domain_suffix() {
    local str="$1"
    local normalized="${str#.}"

    is_domain "$normalized"
}

# Checks if the given string is a valid base64-encoded sequence
is_base64() {
    local str="$1"

    if echo "$str" | base64 -d > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Checks if the given string looks like a Shadowsocks userinfo
is_shadowsocks_userinfo_format() {
    local str="$1"
    local regex='^[^:]+:[^:]+(:[^:]+)?$'

    [[ "$str" =~ $regex ]]
}

# Compares the current package version with the required minimum
is_min_package_version() {
    local current="$1"
    local required="$2"

    local lowest
    lowest="$(printf '%s\n' "$current" "$required" | sort -V | head -n1)"

    [ "$lowest" = "$required" ]
}

# Checks if the given file exists
file_exists() {
    local filepath="$1"

    if [[ -f "$filepath" ]]; then
        return 0
    else
        return 1
    fi
}

# Checks if a service script exists in /etc/init.d
service_exists() {
    local service="$1"

    if [ -x "/etc/init.d/$service" ]; then
        return 0
    else
        return 1
    fi
}

# Returns the inbound tag name by appending the postfix to the given section
get_inbound_tag_by_section() {
    local section="$1"
    local postfix="in"

    echo "$section-$postfix"
}

# Returns the outbound tag name by appending the postfix to the given section
get_outbound_tag_by_section() {
    local section="$1"
    local postfix="out"

    echo "$section-$postfix"
}

# Constructs and returns a domain resolver tag by appending a fixed postfix to the given section
get_domain_resolver_tag() {
    local section="$1"
    local postfix="domain-resolver"

    echo "$section-$postfix"
}

# Converts a comma-separated string into a JSON array string
comma_string_to_json_array() {
    local input="$1"

    if [ -z "$input" ]; then
        echo "[]"
        return
    fi

    local replaced="${input//,/\",\"}"

    echo "[\"$replaced\"]"
}

# Percent-decodes a single URL component, e.g. a password or a query parameter value.
# Only %XX is decoded. "+" is left alone: in userinfo and in a path it is a literal character, not a
# space, and turning it into a space corrupted every password containing one. Backslashes are escaped
# first, so that printf does not reinterpret a value like 'c:\path\new' as containing a newline.
# Must be applied to the pieces of a URL, never to the whole URL: decoding first would let a %40 in a
# password turn into an "@" and move the host/userinfo boundary.
url_decode() {
    local encoded="$1"

    printf '%b' "$(printf '%s' "$encoded" | sed -e 's/\\/\\\\/g' -e 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

# Returns the scheme (protocol) part of a URL
url_get_scheme() {
    local url="$1"
    echo "${url%%://*}"
}

# Extracts the userinfo (username[:password]) part from a URL
url_get_userinfo() {
    local url="$1"
    echo "$url" | sed -n -e 's#^[^:/?]*://##' -e '/@/!d' -e 's/@.*//p'
}

# Extracts the host part from a URL
url_get_host() {
    local url="$1"

    url="${url#*://}"
    url="${url#*@}"
    url="${url%%[/?#]*}"

    echo "${url%%:*}"
}

# Extracts the port number from a URL
url_get_port() {
    local url="$1"

    url="${url#*://}"
    url="${url#*@}"
    url="${url%%[/?#]*}"

    [[ "$url" == *:* ]] && echo "${url#*:}" || echo ""
}

# Extracts the path from a URL (without query or fragment; returns "/" if empty)
url_get_path() {
    local url="$1"
    echo "$url" | sed -n -e 's#^[^:/?]*://##' -e 's#^[^/]*##' -e 's#\([^?]*\).*#\1#p'
}

# Extracts the value of a specific query parameter from a URL
url_get_query_param() {
    local url="$1"
    local param="$2"

    local raw
    raw=$(echo "$url" | sed -n "s/.*[?&]$param=\([^&?#]*\).*/\1/p")

    [ -z "$raw" ] && echo "" && return

    url_decode "$raw"
}

# Extracts the basename (filename without extension) from a URL
# The query string and the fragment are not part of the file name: GitHub links often end in ?raw=true
url_get_basename() {
    local url="${1%%[?#]*}"

    local filename="${url##*/}"
    local basename="${filename%%.*}"

    echo "$basename"
}

# Extracts and returns the file extension from the given URL
# Lowercase, without the query string and the fragment: list.SRS and list.srs?raw=true are rule sets,
# not plain-text lists
url_get_file_extension() {
    local url="${1%%[?#]*}"

    local basename="${url##*/}"
    case "$basename" in
    *.*) echo "${basename##*.}" | tr 'A-Z' 'a-z' ;;
    *) echo "" ;;
    esac
}

# Remove url fragment (everything after the first '#')
url_strip_fragment() {
    local url="$1"

    echo "${url%%#*}"
}

# Decodes and returns a base64-encoded string
# Decodes base64, also in the URL-safe alphabet and without padding: SIP002 shadowsocks links use
# base64url, and BusyBox/coreutils base64 stop at "-" or "_", which silently cut the password short.
# Returns non-zero when the input cannot be decoded.
base64_decode() {
    local str="$1"

    str="$(printf '%s' "$str" | tr -- '-_' '+/')"
    case $((${#str} % 4)) in
    2) str="$str==" ;;
    3) str="$str=" ;;
    1) return 1 ;;
    esac

    printf '%s' "$str" | base64 -d 2> /dev/null
}

# Generates a unique 16-character ID based on the current timestamp and a random number
gen_id() {
    printf '%s%s' "$(date +%s)" "$RANDOM" | md5sum | cut -c1-16
}

# Adds a missing UCI option with the given value if it does not exist
migration_add_new_option() {
    local package="$1"
    local section="$2"
    local option="$3"
    local value="$4"

    local current
    current="$(uci -q get "$package.$section.$option")"
    if [ -z "$current" ]; then
        log "Adding missing option '$option' with value '$value'"
        uci set "$package.$section.$option=$value"
        uci commit "$package"
        return 0
    else
        return 1
    fi
}

# Migrates a configuration key in an OpenWrt config file from old_key_name to new_key_name
migration_rename_config_key() {
    local config="$1"
    local key_type="$2"
    local old_key_name="$3"
    local new_key_name="$4"

    if grep -q "$key_type $old_key_name" "$config"; then
        log "Deprecated $key_type found: $old_key_name migrating to $new_key_name"
        sed -i "s/$key_type $old_key_name/$key_type $new_key_name/g" "$config"
    fi
}

# Download URL to file
# curl is used instead of wget: uclient-fetch fails on HTTPS through an HTTP proxy when the server redirects,
# which GitHub release downloads do
download_to_file() {
    local url="$1"
    local filepath="$2"
    local http_proxy_address="$3"
    local retries="${4:-3}"
    local wait="${5:-2}"

    local attempt direct_fallback
    config_get_bool direct_fallback "settings" "download_lists_direct_fallback" 0
    for attempt in $(seq 1 "$retries"); do
        if [ -n "$http_proxy_address" ]; then
            curl -fsSL --connect-timeout 15 --max-time 120 -x "http://$http_proxy_address" -o "$filepath" "$url" &&
                return 0

            if [ "$direct_fallback" -eq 1 ]; then
                log "Attempt $attempt/$retries to download $url through the proxy failed, trying directly" "warn"
                curl -fsSL --connect-timeout 15 --max-time 120 -o "$filepath" "$url" && return 0
            fi
        else
            curl -fsSL --connect-timeout 15 --max-time 120 -o "$filepath" "$url" && return 0
        fi

        log "Attempt $attempt/$retries to download $url failed" "warn"
        sleep "$wait"
    done

    return 1
}

# Converts Windows-style line endings (CRLF) to Unix-style (LF)
convert_crlf_to_lf() {
    local filepath="$1"

    if grep -q $'\r' "$filepath"; then
        log "File '$filepath' contains CRLF line endings. Converting to LF..." "debug"
        local tmpfile
        tmpfile=$(mktemp)
        tr -d '\r' < "$filepath" > "$tmpfile" && mv "$tmpfile" "$filepath" || rm -f "$tmpfile"
    fi
}
