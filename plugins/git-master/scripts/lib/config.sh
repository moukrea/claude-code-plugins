#!/usr/bin/env bash
set -euo pipefail

# config.sh — Hierarchical YAML config loading, merging, and querying for git-master.
#
# Provides:
#   gm_config_load        — merge all config layers, write cached JSON
#   gm_config_get         — query a scalar value by dot-path
#   gm_config_get_array   — query an array value, one element per line
#   gm_config_get_json    — query a JSON subtree by dot-path
#   gm_config_reload      — force cache invalidation and reload
#
# Config files are loaded in order of ascending priority:
#   1. Factory defaults:  ${CLAUDE_PLUGIN_ROOT}/defaults/config.yml
#   2. User global:       ~/.config/git-master/config.yml
#   3. Git root project:  <git-root>/.git-master.yml
#   4. Ancestor walk:     .git-master.yml from CWD up to (but not including) git root
#
# Environment variable overrides (highest priority):
#   GIT_MASTER_*  with double-underscore path syntax
#   e.g. GIT_MASTER_COMMIT__CONVENTION=angular  =>  commit.convention = "angular"

###############################################################################
# Internal helpers
###############################################################################

_gm_log() {
    if [[ "${GIT_MASTER_DEBUG:-0}" == "1" ]]; then
        printf '[git-master:config] %s\n' "$*" >&2
    fi
}

_gm_error() {
    printf '[git-master:config] ERROR: %s\n' "$*" >&2
}

# Find the git repository root, or return 1 if not in a repo.
_gm_git_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Collect all config file paths in merge order (lowest to highest priority).
# Prints one path per line; only includes files that actually exist.
_gm_config_sources() {
    local git_root
    git_root="$(_gm_git_root)" || true

    # 1. Factory defaults
    local factory="${CLAUDE_PLUGIN_ROOT:-}/defaults/config.yml"
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "$factory" ]]; then
        printf '%s\n' "$factory"
    fi

    # 2. User global
    local user_global="${HOME}/.config/git-master/config.yml"
    if [[ -f "$user_global" ]]; then
        printf '%s\n' "$user_global"
    fi

    # 3. Git root project-level config
    if [[ -n "$git_root" && -f "${git_root}/.git-master.yml" ]]; then
        printf '%s\n' "${git_root}/.git-master.yml"
    fi

    # 4. Ancestor walk from CWD up to (but not including) git root.
    #    Collected in root-to-CWD order so that closer-to-CWD = higher priority.
    if [[ -n "$git_root" ]]; then
        local cwd
        cwd="$(pwd)"
        local norm_root
        norm_root="$(cd "$git_root" && pwd)"

        # Only walk if CWD is strictly inside the git root (not equal to it).
        if [[ "$cwd" != "$norm_root" && "$cwd" == "$norm_root"/* ]]; then
            local -a ancestor_configs=()
            local dir="$cwd"
            while [[ "$dir" != "$norm_root" && -n "$dir" ]]; do
                if [[ -f "${dir}/.git-master.yml" ]]; then
                    ancestor_configs+=("${dir}/.git-master.yml")
                fi
                dir="$(dirname "$dir")"
            done

            # Reverse so that outermost ancestor is printed first (lower priority)
            # and CWD is printed last (highest priority among file sources).
            local i
            for (( i=${#ancestor_configs[@]}-1; i>=0; i-- )); do
                printf '%s\n' "${ancestor_configs[$i]}"
            done
        fi
    fi
}

# Compute a cache-key hash from the mtimes of all source files plus relevant
# env vars.  Uses md5sum if available, else cksum.
_gm_config_hash() {
    local sources
    sources="$(_gm_config_sources)"

    local mtime_data=""
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local mt
        if mt="$(stat -c '%Y' "$f" 2>/dev/null)"; then
            mtime_data+="${f}:${mt};"
        elif mt="$(stat -f '%m' "$f" 2>/dev/null)"; then
            # macOS stat
            mtime_data+="${f}:${mt};"
        else
            # Last resort: always invalidate
            mtime_data+="${f}:${RANDOM};"
        fi
    done <<< "$sources"

    # Include GIT_MASTER_* env vars in the hash so overrides bust the cache.
    local env_overrides
    env_overrides="$(env | grep -E '^GIT_MASTER_' | sort 2>/dev/null || true)"
    mtime_data+="$env_overrides"

    if command -v md5sum &>/dev/null; then
        printf '%s' "$mtime_data" | md5sum | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        # macOS
        printf '%s' "$mtime_data" | md5
    elif command -v cksum &>/dev/null; then
        printf '%s' "$mtime_data" | cksum | cut -d' ' -f1
    else
        printf '%s' "$RANDOM"
    fi
}

###############################################################################
# Embedded Python merger
###############################################################################

# Run the embedded Python script that deep-merges all YAML sources and applies
# env overrides, outputting the final merged config as JSON on stdout.
_gm_merge_with_python() {
    local sources_arg="$1"  # newline-separated list of file paths

    python3 - "$sources_arg" <<'PYTHON_HEREDOC'
import sys
import os
import json

try:
    import yaml
except ImportError:
    print("__PYYAML_MISSING__", file=sys.stderr)
    sys.exit(99)


def deep_merge(base, override):
    """Deep-merge override into base.

    - Scalars: override wins.
    - Dicts: recursively merged.
    - Lists: override replaces entirely.
    - An explicit None in override clears the key.
    """
    if not isinstance(base, dict) or not isinstance(override, dict):
        return override

    merged = dict(base)
    for key, val in override.items():
        if val is None:
            merged.pop(key, None)
        elif key in merged and isinstance(merged[key], dict) and isinstance(val, dict):
            merged[key] = deep_merge(merged[key], val)
        else:
            merged[key] = val
    return merged


def parse_env_overrides():
    """Collect GIT_MASTER_* env vars and convert to a nested dict.

    Double underscores delimit path segments:
        GIT_MASTER_COMMIT__CONVENTION=angular  ->  {"commit": {"convention": "angular"}}
    """
    overrides = {}
    prefix = "GIT_MASTER_"
    skip = {"GIT_MASTER_DEBUG"}

    for name, value in os.environ.items():
        if not name.startswith(prefix):
            continue
        if name in skip:
            continue

        key_path = name[len(prefix):].lower().split("__")
        if not key_path or key_path == [""]:
            continue

        # Attempt to interpret the value as JSON for typed values.
        try:
            typed_value = json.loads(value)
        except (json.JSONDecodeError, ValueError):
            typed_value = value

        d = overrides
        for segment in key_path[:-1]:
            d = d.setdefault(segment, {})
        d[key_path[-1]] = typed_value

    return overrides


def main():
    sources_arg = sys.argv[1] if len(sys.argv) > 1 else ""
    source_files = [p.strip() for p in sources_arg.strip().split("\n") if p.strip()]

    merged = {}
    for path in source_files:
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r") as fh:
                data = yaml.safe_load(fh)
            if isinstance(data, dict):
                merged = deep_merge(merged, data)
            # If the file is empty or not a dict, skip it silently.
        except Exception as exc:
            print(f"Warning: failed to parse {path}: {exc}", file=sys.stderr)

    # Apply env var overrides as highest-priority layer.
    env_layer = parse_env_overrides()
    if env_layer:
        merged = deep_merge(merged, env_layer)

    json.dump(merged, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
PYTHON_HEREDOC
}

###############################################################################
# Fallback: basic parser (no PyYAML available)
###############################################################################

# Very rudimentary YAML parser that handles top-level scalars and one level of
# nesting.  Used as a last resort so that basic settings still work when
# python3 is unavailable or PyYAML is not installed.
_gm_merge_fallback() {
    local sources="$1"

    local -a files=()
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        [[ -f "$f" ]] && files+=("$f")
    done <<< "$sources"

    if [[ ${#files[@]} -eq 0 ]]; then
        printf '{}\n'
        return
    fi

    # Parse only the highest-priority file to keep things simple.
    local target="${files[-1]}"
    _gm_log "Fallback: parsing $target with basic parser"

    # If python3 is available (just without PyYAML), use it for the basic
    # parsing since it handles edge cases better than pure sed/awk.
    if command -v python3 &>/dev/null; then
        python3 - "$target" <<'FALLBACK_PY'
import sys
import json
import re

result = {}
parent = None
path = sys.argv[1]

try:
    with open(path) as fh:
        for raw_line in fh:
            stripped = raw_line.rstrip("\n\r")
            # Skip blank lines and comments.
            trimmed = stripped.lstrip()
            if not trimmed or trimmed.startswith("#"):
                continue

            indent = len(stripped) - len(trimmed)

            # Remove inline comments (but not inside quoted strings — best effort).
            content = re.sub(r'\s+#[^"\']*$', "", trimmed).strip()
            if ":" not in content:
                continue

            key, _, val = content.partition(":")
            key = key.strip()
            val = val.strip()

            # Strip surrounding quotes.
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                val = val[1:-1]

            if indent == 0:
                if val:
                    # Attempt to cast booleans and numbers.
                    if val.lower() in ("true", "yes"):
                        result[key] = True
                    elif val.lower() in ("false", "no"):
                        result[key] = False
                    elif val.lower() in ("null", "~"):
                        result[key] = None
                    else:
                        try:
                            result[key] = int(val)
                        except ValueError:
                            try:
                                result[key] = float(val)
                            except ValueError:
                                result[key] = val
                    parent = None
                else:
                    parent = key
                    if key not in result or not isinstance(result[key], dict):
                        result[key] = {}
            elif parent is not None and indent > 0 and val:
                if val.lower() in ("true", "yes"):
                    result[parent][key] = True
                elif val.lower() in ("false", "no"):
                    result[parent][key] = False
                elif val.lower() in ("null", "~"):
                    result[parent][key] = None
                else:
                    try:
                        result[parent][key] = int(val)
                    except ValueError:
                        try:
                            result[parent][key] = float(val)
                        except ValueError:
                            result[parent][key] = val
except Exception:
    pass

json.dump(result, sys.stdout, indent=2)
sys.stdout.write("\n")
FALLBACK_PY
        return
    fi

    # Pure bash/sed/awk fallback — extremely minimal.
    # Only extracts top-level "key: value" lines into a flat JSON object.
    _gm_log "Fallback: pure bash parser (no python3)"
    local json_body=""
    local first=1
    while IFS= read -r line; do
        # Skip comments and blank lines.
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        # Only top-level (no leading whitespace) "key: value" lines.
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_-]*):\ +(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip inline comment.
            val="${val%%#*}"
            val="${val%"${val##*[![:space:]]}"}"  # trim trailing whitespace
            # Strip quotes.
            if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            if [[ $first -eq 1 ]]; then
                first=0
            else
                json_body+=","
            fi
            # Escape double quotes in value.
            val="${val//\\/\\\\}"
            val="${val//\"/\\\"}"
            json_body+="$(printf '\n  "%s": "%s"' "$key" "$val")"
        fi
    done < "$target"

    printf '{%s\n}\n' "$json_body"
}

###############################################################################
# Public API
###############################################################################

# gm_config_load — Merge all config layers, write the cached JSON file, and
#                  export GIT_MASTER_CONFIG_PATH.
gm_config_load() {
    local data_dir="${CLAUDE_PLUGIN_DATA:-/tmp}"
    local cache_json="${data_dir}/git-master-config.json"
    local cache_hash_file="${data_dir}/git-master-config.hash"

    # Compute current hash.
    local current_hash
    current_hash="$(_gm_config_hash)"

    # Check cache validity.
    if [[ -f "$cache_json" && -f "$cache_hash_file" ]]; then
        local stored_hash
        stored_hash="$(cat "$cache_hash_file" 2>/dev/null || true)"
        if [[ "$stored_hash" == "$current_hash" ]]; then
            _gm_log "Cache hit (hash=$current_hash)"
            export GIT_MASTER_CONFIG_PATH="$cache_json"
            return 0
        fi
    fi

    _gm_log "Cache miss — merging config sources"

    # Collect sources as newline-separated string.
    local sources
    sources="$(_gm_config_sources)"

    if [[ -z "$sources" ]]; then
        _gm_log "No config sources found; writing empty config"
        printf '{}\n' > "$cache_json"
        printf '%s' "$current_hash" > "$cache_hash_file"
        export GIT_MASTER_CONFIG_PATH="$cache_json"
        return 0
    fi

    _gm_log "Sources:"
    local _s
    while IFS= read -r _s; do
        [[ -n "$_s" ]] && _gm_log "  $_s"
    done <<< "$sources"

    # Attempt merge with Python + PyYAML.
    local merged_json=""
    local python_exit=0
    local python_stderr_file=""

    if command -v python3 &>/dev/null; then
        python_stderr_file="$(mktemp "${TMPDIR:-/tmp}/gm-config-stderr.XXXXXX")"
        merged_json="$(_gm_merge_with_python "$sources" 2>"$python_stderr_file")" || python_exit=$?
        local stderr_content
        stderr_content="$(cat "$python_stderr_file" 2>/dev/null || true)"
        rm -f "$python_stderr_file"

        if [[ $python_exit -eq 99 ]] || [[ "$stderr_content" == *"__PYYAML_MISSING__"* ]]; then
            _gm_log "PyYAML not available — falling back to basic parser"
            merged_json=""
            python_exit=1
        elif [[ $python_exit -ne 0 ]]; then
            _gm_error "Python merge failed (exit $python_exit)"
            [[ -n "$stderr_content" ]] && _gm_error "$stderr_content"
            merged_json=""
        fi
    else
        _gm_log "python3 not found — falling back to basic parser"
        python_exit=1
    fi

    # Fallback if Python path failed.
    if [[ -z "$merged_json" || $python_exit -ne 0 ]]; then
        merged_json="$(_gm_merge_fallback "$sources")"
    fi

    # Validate JSON before writing.
    if command -v jq &>/dev/null; then
        if ! printf '%s' "$merged_json" | jq . >/dev/null 2>&1; then
            _gm_error "Merged config is not valid JSON; writing empty object"
            merged_json='{}'
        fi
    fi

    # Ensure data directory exists.
    mkdir -p "$data_dir" 2>/dev/null || true

    printf '%s\n' "$merged_json" > "$cache_json"
    printf '%s' "$current_hash" > "$cache_hash_file"

    export GIT_MASTER_CONFIG_PATH="$cache_json"
    _gm_log "Config cached at $cache_json"
}

# gm_config_reload — Force cache invalidation and reload.
gm_config_reload() {
    local data_dir="${CLAUDE_PLUGIN_DATA:-/tmp}"
    rm -f "${data_dir}/git-master-config.json" "${data_dir}/git-master-config.hash"
    _gm_log "Cache invalidated — reloading"
    gm_config_load
}

# gm_config_get <dotpath> — Return a single scalar value.
#   e.g.  gm_config_get commit.convention   =>  "conventional"
#   Returns empty string and exit 1 if path does not exist or value is null.
gm_config_get() {
    local dotpath="${1:?Usage: gm_config_get <dotpath>}"

    # Ensure config is loaded.
    if [[ -z "${GIT_MASTER_CONFIG_PATH:-}" || ! -f "${GIT_MASTER_CONFIG_PATH:-}" ]]; then
        gm_config_load
    fi

    if ! command -v jq &>/dev/null; then
        _gm_error "jq is required for gm_config_get"
        return 1
    fi

    # Convert dot-path to jq filter: "commit.convention" => ".commit.convention"
    local jq_filter
    jq_filter="$(printf '.%s' "$dotpath")"

    # Check if the path exists.  We cannot use `// empty` or `-e` because both
    # treat `false`, `null`, and `0` as falsy.  Instead we test whether the
    # path resolves to something other than the jq error case.
    local exists
    exists="$(jq "($jq_filter | type) // \"__missing__\"" "$GIT_MASTER_CONFIG_PATH" 2>/dev/null)" || return 1
    if [[ "$exists" == '"__missing__"' || "$exists" == "__missing__" ]]; then
        return 1
    fi

    local result
    result="$(jq -r "$jq_filter" "$GIT_MASTER_CONFIG_PATH" 2>/dev/null)" || return 1

    # jq -r prints "null" for JSON null.  We treat explicit null as "cleared",
    # meaning the key was intentionally set to null, so return exit 1.
    if [[ "$result" == "null" ]]; then
        return 1
    fi

    printf '%s\n' "$result"
}

# gm_config_get_array <dotpath> — Return array elements, one per line.
#   e.g.  gm_config_get_array commit.types
#   Returns exit 1 if path does not exist or is not an array.
gm_config_get_array() {
    local dotpath="${1:?Usage: gm_config_get_array <dotpath>}"

    if [[ -z "${GIT_MASTER_CONFIG_PATH:-}" || ! -f "${GIT_MASTER_CONFIG_PATH:-}" ]]; then
        gm_config_load
    fi

    if ! command -v jq &>/dev/null; then
        _gm_error "jq is required for gm_config_get_array"
        return 1
    fi

    local jq_filter
    jq_filter="$(printf '.%s' "$dotpath")"

    local result
    result="$(jq -r "($jq_filter // null) | if type == \"array\" then .[] else empty end" \
        "$GIT_MASTER_CONFIG_PATH" 2>/dev/null)" || true

    if [[ -z "$result" ]]; then
        return 1
    fi

    printf '%s\n' "$result"
}

# gm_config_get_json <dotpath> — Return a JSON subtree.
#   e.g.  gm_config_get_json commit   =>  { "convention": "conventional", ... }
#   Returns exit 1 if path does not exist.
gm_config_get_json() {
    local dotpath="${1:?Usage: gm_config_get_json <dotpath>}"

    if [[ -z "${GIT_MASTER_CONFIG_PATH:-}" || ! -f "${GIT_MASTER_CONFIG_PATH:-}" ]]; then
        gm_config_load
    fi

    if ! command -v jq &>/dev/null; then
        _gm_error "jq is required for gm_config_get_json"
        return 1
    fi

    local jq_filter
    jq_filter="$(printf '.%s' "$dotpath")"

    # Check if the path exists (handles false/0/null correctly).
    local exists
    exists="$(jq "($jq_filter | type) // \"__missing__\"" "$GIT_MASTER_CONFIG_PATH" 2>/dev/null)" || return 1
    if [[ "$exists" == '"__missing__"' || "$exists" == "__missing__" ]]; then
        return 1
    fi

    local result
    result="$(jq "$jq_filter" "$GIT_MASTER_CONFIG_PATH" 2>/dev/null)" || return 1

    printf '%s\n' "$result"
}
