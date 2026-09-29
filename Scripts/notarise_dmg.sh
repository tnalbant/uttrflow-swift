#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

images=(dist/Uttrflow-*.dmg)
if [[ ! -e "${images[0]}" ]]; then
    echo "error: no disk image in dist/. Build one first with: make dmg" >&2
    exit 1
fi

if (( ${#images[@]} != 1 )); then
    echo "error: more than one disk image in dist/, and no way to tell which you meant:" >&2
    printf '    %s\n' "${images[@]}" >&2
    echo "  Name one: ./Scripts/notarise.sh dist/Uttrflow-<version>.dmg" >&2
    echo "  Or start over: make clean" >&2
    exit 1
fi

exec ./Scripts/notarise.sh "${images[0]}"
