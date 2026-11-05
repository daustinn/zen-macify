#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH="${1:-}"

get_zen_profile() {
    if [ -n "$PROFILE_PATH" ] && [ -d "$PROFILE_PATH" ]; then
        echo "$PROFILE_PATH"
        return
    fi

    local zen_dir=""
    if [ -n "${APPDATA:-}" ]; then
        zen_dir="$APPDATA/zen"
    elif [ -d "$HOME/AppData/Roaming/zen" ]; then
        zen_dir="$HOME/AppData/Roaming/zen"
    elif [ -d "$HOME/.zen" ]; then
        zen_dir="$HOME/.zen"
    else
        echo "Error: Zen directory not found." >&2
        exit 1
    fi

    local profiles_ini="$zen_dir/profiles.ini"
    local selected=""

    if [ -f "$profiles_ini" ]; then
        local install_default
        install_default=$(grep -E '^Default=Profiles/' "$profiles_ini" | head -n1 | cut -d= -f2 || true)
        if [ -n "$install_default" ] && [ -d "$zen_dir/$install_default" ]; then
            selected="$zen_dir/$install_default"
        fi
    fi

    if [ -z "$selected" ] && [ -d "$zen_dir/Profiles" ]; then
        selected=$(find "$zen_dir/Profiles" -mindepth 1 -maxdepth 1 -type d | grep -E 'release|default' | head -n1 || true)
    fi

    if [ -z "$selected" ]; then
        echo "Error: Could not locate Zen Browser profile folder." >&2
        exit 1
    fi

    echo "$selected"
}

TARGET_PROFILE="$(get_zen_profile)"
echo "Target Zen profile: $TARGET_PROFILE"

CHROME_DIR="$TARGET_PROFILE/chrome"
mkdir -p "$CHROME_DIR"
TARGET_FILE="$CHROME_DIR/zen-themes.css"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
CSS_CONTENT=""

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/chrome.css" ]; then
    echo "Reading local chrome.css from: $SCRIPT_DIR/chrome.css"
    CSS_CONTENT=$(cat "$SCRIPT_DIR/chrome.css")
elif [ -f "./chrome.css" ]; then
    echo "Reading local chrome.css from: ./chrome.css"
    CSS_CONTENT=$(cat "./chrome.css")
else
    echo "Downloading chrome.css from GitHub..."
    CSS_CONTENT=$(curl -fsSL "https://raw.githubusercontent.com/daustinn/zen-macify/main/chrome.css")
fi

START_MARKER="/* === START ZEN MACIFY === */"
END_MARKER="/* === END ZEN MACIFY === */"
WRAPPED_CONTENT="$START_MARKER
$CSS_CONTENT
$END_MARKER"

if [ -f "$TARGET_FILE" ] && grep -qF "$START_MARKER" "$TARGET_FILE" && grep -qF "$END_MARKER" "$TARGET_FILE"; then
    python3 -c "
import sys, re
start, end = sys.argv[1], sys.argv[2]
block = sys.argv[3]
path = sys.argv[4]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
pattern = re.escape(start) + r'.*?' + re.escape(end)
updated = re.sub(pattern, block, content, flags=re.DOTALL)
with open(path, 'w', encoding='utf-8') as f:
    f.write(updated)
" "$START_MARKER" "$END_MARKER" "$WRAPPED_CONTENT" "$TARGET_FILE" 2>/dev/null || {
        # Fallback if python3 is not available
        awk -v start="$START_MARKER" -v end="$END_MARKER" -v block="$WRAPPED_CONTENT" '
            $0 ~ start { printing=0; print block; next }
            $0 ~ end { printing=1; next }
            printing { print }
        ' printing=1 "$TARGET_FILE" > "${TARGET_FILE}.tmp" && mv "${TARGET_FILE}.tmp" "$TARGET_FILE"
    }
    echo "Updated Zen Macify section in $TARGET_FILE"
elif [ -f "$TARGET_FILE" ]; then
    printf "\n%s\n" "$WRAPPED_CONTENT" >> "$TARGET_FILE"
    echo "Appended Zen Macify to $TARGET_FILE"
else
    printf "%s\n" "$WRAPPED_CONTENT" > "$TARGET_FILE"
    echo "Created $TARGET_FILE with Zen Macify content"
fi

echo "Done. Please restart Zen Browser to apply changes."
