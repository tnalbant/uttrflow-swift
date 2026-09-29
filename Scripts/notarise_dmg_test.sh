#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

cp "$repo_root/Makefile" "$temporary/Makefile"
cp -R "$repo_root/Scripts" "$temporary/Scripts"
cp "$temporary/Scripts/notarise.sh" "$temporary/notarise-real.sh"
cat > "$temporary/Scripts/notarise.sh" <<'EOF'
#!/usr/bin/env bash
printf 'notarised target: %s\n' "$*"
EOF
chmod +x "$temporary/Scripts/notarise.sh"
mkdir -p "$temporary/dist"

expect_failure() {
    local expected="$1"
    shift
    local output
    if output="$(cd "$temporary" && "$@" 2>&1)"; then
        echo "error: command unexpectedly succeeded; wanted: $expected" >&2
        exit 1
    fi
    if ! grep -Fq "$expected" <<<"$output"; then
        echo "error: command did not report '$expected':" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi
}

expect_failure "no disk image in dist/" make notarise-dmg
expect_failure "no disk image in dist/" "$temporary/Scripts/notarise_dmg.sh"

: > "$temporary/dist/Uttrflow-2026.10.1.dmg"
single="$(cd "$temporary" && make -n notarise-dmg)"
grep -Fq './Scripts/notarise_dmg.sh' <<<"$single"
single="$(cd "$temporary" && "$temporary/Scripts/notarise_dmg.sh")"
grep -Fq 'notarised target: dist/Uttrflow-2026.10.1.dmg' <<<"$single"

: > "$temporary/dist/Uttrflow-2026.9.14.dmg"
expect_failure "more than one disk image in dist/" make notarise-dmg
expect_failure "more than one disk image in dist/" "$temporary/Scripts/notarise_dmg.sh"
expect_failure "expected one target" "$temporary/notarise-real.sh" \
    --check dist/Uttrflow-2026.10.1.dmg dist/Uttrflow-2026.9.14.dmg

echo "notarise-dmg test passed: zero, one, and multiple images are handled explicitly"
