#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
configured_developer_dir="$test_root/configured-xcode"
ln -s "$(xcode-select -p)" "$configured_developer_dir"

cat > "$test_root/probe.mk" <<'MAKE'
.PHONY: print-developer-dir
print-developer-dir:
	@printf '%s\n' "$$DEVELOPER_DIR"
MAKE

check_developer_dir() {
    local expected="$1"
    shift
    local actual
    actual="$(cd "$repo_root" && env "$@" make --no-print-directory -s -f Makefile -f "$test_root/probe.mk" print-developer-dir)"

    if [[ "$actual" != "$expected" ]]; then
        printf 'error: expected DEVELOPER_DIR=%s, got %s\n' "$expected" "$actual" >&2
        return 1
    fi
}

check_developer_dir "$configured_developer_dir" "DEVELOPER_DIR=$configured_developer_dir"
check_developer_dir "/Applications/Xcode.app/Contents/Developer" -u DEVELOPER_DIR

printf 'Makefile developer directory test passed\n'
