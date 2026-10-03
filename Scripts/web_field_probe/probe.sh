#!/usr/bin/env bash
#
# Measures whether an Accessibility write into a script-controlled web field reaches the page's own state,
# not only the text it shows. Results and how to read them: Docs/insertion.md, "A web field's own state".
#
# Usage:  Scripts/web_field_probe/probe.sh
#
# Needs Accessibility granted to the terminal it runs from, Google Chrome in /Applications and an unlocked
# screen: while the screen is locked the web views publish no fields and every case prints "no field found".
# Every window opens in the background and every write and key press goes to that one process,
# so nothing reaches the application in front. Chrome runs on a throwaway profile.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d -t uttrflow-web-field.XXXXXX)"
PORT=8765
REPORT="$WORK/report.json"

xcrun swiftc -O -o "$WORK/ax_write" "$HERE/ax_write.swift"
xcrun swiftc -O -o "$WORK/webview" "$HERE/webview.swift"
python3 "$HERE/serve.py" "$PORT" "$REPORT" &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

# Opens the fixture in the background and prints the pid of the process that owns its window.
open_page() {
    local engine="$1" url="$2"
    case "$engine" in
        chrome)
            open -g -n -a "Google Chrome" --args --user-data-dir="$WORK/chrome-profile" \
                --no-first-run --no-default-browser-check "$url"
            for _ in $(seq 1 60); do [[ -s "$REPORT" ]] && break; sleep 0.25; done
            ps -axo pid=,command= | grep -F "$WORK/chrome-profile" | grep -v -e "--type=" -e grep \
                | awk '{print $1}' | head -1
            ;;
        webkit)
            "$WORK/webview" "$url" >/dev/null 2>&1 &
            local pid=$!
            for _ in $(seq 1 60); do [[ -s "$REPORT" ]] && break; sleep 0.25; done
            echo "$pid"
            ;;
    esac
}

for engine in chrome webkit; do
    for attribute in selected value; do
        for field in input editable model; do
            rm -f "$REPORT"
            rm -rf "$WORK/chrome-profile"
            pid="$(open_page "$engine" "http://127.0.0.1:$PORT/controlled_field.html?field=$field")"
            sleep 1
            echo "== $engine, $field, AX$attribute"
            "$WORK/ax_write" "$pid" "$attribute" "one two three"
            sleep 1
            echo "page after write:     $(cat "$REPORT")"
            "$WORK/ax_write" "$pid" key "x"
            sleep 1
            echo "page after key press: $(cat "$REPORT")"
            kill "$pid" 2>/dev/null
            sleep 1
        done
    done
done
