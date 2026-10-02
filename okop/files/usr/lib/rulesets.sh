# shellcheck shell=busybox
# Constructs and returns a ruleset tag using section, name, optional type, and a fixed postfix
get_ruleset_tag() {
    local section="$1"
    local name="$2"
    local type="$3"
    local postfix="ruleset"

    if [ -n "$type" ]; then
        echo "$section-$name-$type-$postfix"
    else
        echo "$section-$name-$postfix"
    fi
}

# Creates a new ruleset JSON file if it doesn't already exist
create_source_rule_set() {
    local ruleset_filepath="$1"

    if file_exists "$ruleset_filepath"; then
        return 3
    fi

    jq -n '{version: 3, rules: []}' > "$ruleset_filepath"
}

# Turns a plain list into one valid entry per line, in one pass (a fork per line made lists of tens of
# thousands of entries take minutes). Comments ("//" or "#" at the start or after a blank), carriage
# returns and blanks are removed, entries may also be separated by commas. Domains are lowercased and lose
# a scheme, path and port, so "Example.com" and "https://example.com/page" work; "*.example.com" becomes
# ".example.com". Invalid entries are dropped.
normalize_plain_list() {
    local input="$1"
    local output="$2"
    local type="$3"

    awk -v type="$type" '
        function emit(entry,    parts, count, i, dot) {
            if (type == "domains") {
                entry = tolower(entry)
                sub(/^[a-z][a-z0-9+.-]*:\/\//, "", entry)
                sub(/[\/:?#].*$/, "", entry)
                # ".example.com" (and "*.example.com") is a suffix of subdomains only
                sub(/^\*\./, ".", entry)
                dot = substr(entry, 1, 1) == "." ? "." : ""
                entry = substr(entry, length(dot) + 1)
                if (entry ~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/)
                    print dot entry
                return
            }

            if (entry !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/)
                return
            count = split(entry, parts, /[.\/]/)
            for (i = 1; i <= 4; i++)
                if (parts[i] + 0 > 255)
                    return
            if (count == 5 && parts[5] + 0 > 32)
                return
            print entry
        }
        {
            gsub(/\r/, "")
            sub(/(^|[ \t])(\/\/|#).*$/, "")
            count = split($0, entries, /[ \t,]+/)
            for (i = 1; i <= count; i++)
                if (entries[i] != "")
                    emit(entries[i])
        }
    ' "$input" > "$output"
}

# Adds the entries of a normalized list file to a source rule set under the given key. The entries are
# read from the file, not passed as an argument: large user lists exceeded the argument size limit and
# were silently left out.
add_list_file_to_source_ruleset() {
    local list_filepath="$1"
    local ruleset_filepath="$2"
    local key="$3"

    local tmpfile
    tmpfile="$(mktemp)"
    if ! jq --rawfile items "$list_filepath" --arg key "$key" '
        ($items | split("\n") | map(select(length > 0))) as $new
        | (.rules | map(has($key)) | index(true)) as $idx
        | if ($new | length) == 0 then .
          elif $idx != null then .rules[$idx][$key] = (.rules[$idx][$key] + $new | unique)
          else .rules += [{($key): ($new | unique)}]
          end
    ' "$ruleset_filepath" > "$tmpfile"; then
        log "Cannot add $list_filepath to $ruleset_filepath" "error"
        rm -f "$tmpfile"
        return 1
    fi

    mv "$tmpfile" "$ruleset_filepath"
}

# Imports a plain domain list into a source rule set as domain_suffix rules
import_plain_domain_list_to_local_source_ruleset_chunked() {
    local plain_list_filepath="$1"
    local ruleset_filepath="$2"

    local normalized
    normalized="$(mktemp)"
    normalize_plain_list "$plain_list_filepath" "$normalized" "domains"
    log "Adding $(wc -l < "$normalized") domains to rule set at $ruleset_filepath" "debug"
    add_list_file_to_source_ruleset "$normalized" "$ruleset_filepath" "domain_suffix"
    local status=$?
    rm -f "$normalized"
    return $status
}

# Imports a plain subnet list into a source rule set as ip_cidr rules
import_plain_subnet_list_to_local_source_ruleset_chunked() {
    local plain_list_filepath="$1"
    local ruleset_filepath="$2"

    local normalized
    normalized="$(mktemp)"
    normalize_plain_list "$plain_list_filepath" "$normalized" "subnets"
    log "Adding $(wc -l < "$normalized") subnets to rule set at $ruleset_filepath" "debug"
    add_list_file_to_source_ruleset "$normalized" "$ruleset_filepath" "ip_cidr"
    local status=$?
    rm -f "$normalized"
    return $status
}

# Determines the ruleset format based on the file extension (json → source, srs → binary)
get_ruleset_format_by_file_extension() {
    local file_extension="$1"

    local format
    case "$file_extension" in
    json) format="source" ;;
    srs) format="binary" ;;
    *)
        log "Unsupported file extension: .$file_extension" "error"
        return 1
        ;;
    esac

    echo "$format"
}

# Returns the file extension used for a ruleset format (source → json, binary → srs)
get_ruleset_file_extension_by_format() {
    case "$1" in
    source) echo "json" ;;
    binary) echo "srs" ;;
    *) return 1 ;;
    esac
}

# Creates a ruleset file without rules in the given format
create_empty_ruleset_file() {
    local filepath="$1"
    local format="$2"

    local source_tmpfile partfile="$filepath.$$.tmp" status=0
    source_tmpfile="$(mktemp)"
    jq -n '{version: 3, rules: []}' > "$source_tmpfile" || status=1

    if [ "$status" -eq 0 ]; then
        case "$format" in
        source) cp "$source_tmpfile" "$partfile" || status=1 ;;
        binary) sing-box rule-set compile "$source_tmpfile" -o "$partfile" || status=1 ;;
        *) status=1 ;;
        esac
    fi

    # Written next to the target and moved, so that a failure never leaves a damaged file behind
    if [ "$status" -eq 0 ] && mv "$partfile" "$filepath"; then
        rm -f "$source_tmpfile"
        return 0
    fi

    rm -f "$source_tmpfile" "$partfile"
    return 1
}

# Checks that sing-box can read a ruleset file in the given format
is_valid_ruleset_file() {
    local filepath="$1"
    local format="$2"

    [ -s "$filepath" ] || return 1

    case "$format" in
    source) sing-box rule-set compile "$filepath" -o /dev/null > /dev/null 2>&1 ;;
    binary) sing-box rule-set decompile "$filepath" -o /dev/null > /dev/null 2>&1 ;;
    *) return 1 ;;
    esac
}

# Decompiles a sing-box SRS binary file into a JSON ruleset file
decompile_binary_ruleset() {
    local binary_filepath="$1"
    local output_filepath="$2"

    log "Decompiling $binary_filepath to $output_filepath" "debug"
    sing-box rule-set decompile "$binary_filepath" -o "$output_filepath"
    if [[ $? -ne 0 ]]; then
        log "Decompilation command failed for $binary_filepath" "error"
        return 1
    fi
}

# Extracts all ip_cidr entries from a JSON ruleset file and writes them to an output file.
extract_ip_cidr_from_json_ruleset_to_file() {
    local json_file="$1"
    local output_file="$2"

    log "Extracting ip_cidr entries from $json_file to $output_file" "debug"
    # "?" at both levels: a rule set may mix ip_cidr rules with domain rules, and the community lists
    # this project ships do. Without it jq stops at the first rule that has no ip_cidr and nothing,
    # or only the part before that rule, is extracted
    if ! jq -r '.rules[]? | .ip_cidr[]?' "$json_file" > "$output_file"; then
        log "Cannot extract ip_cidr entries from $json_file" "error"
        return 1
    fi

    log "Extracted $(wc -l < "$output_file") ip_cidr entries" "debug"
}
