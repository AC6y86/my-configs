#!/bin/bash
set -euo pipefail

TEST_MODE=false
[[ "${1:-}" == "--test" ]] && TEST_MODE=true

# SSH cert agent differs by platform: WSL bridges Windows fb-sks-agent into
# SSH_AUTH_SOCK via .bashrc; macOS runs fb-sks-agent natively at a known path.
# Prefer the native socket when present (so this works on macOS without .bashrc),
# else fall back to whatever SSH_AUTH_SOCK the environment already set (WSL).
if ! $TEST_MODE; then
    FB_SKS_SOCK="$HOME/.fb-sks-agent/agent.sock"
    if [[ -S "$FB_SKS_SOCK" ]]; then
        export SSH_AUTH_SOCK="$FB_SKS_SOCK"
    elif [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        echo "ERROR: SSH_AUTH_SOCK not set." >&2
        echo "  WSL:   run 'source ~/.bashrc' or open a new terminal." >&2
        echo "  macOS: try '/opt/facebook/bin/fb-sks-agent restart'." >&2
        exit 1
    fi
fi

SSH_USER="joepaley"
HOST="devvm7002.scu0.facebook.com"

# ---- Menu script: runs on the devvm (or locally in test mode) ----
# Assign via `read -r -d ''` rather than $(cat <<'EOF') because macOS's system
# bash 3.2 cannot parse a heredoc nested inside command substitution. `read`
# returns non-zero at EOF with -d '', hence the `|| true`.
IFS='' read -r -d '' REMOTE_SCRIPT <<'ENDSCRIPT' || true
set -euo pipefail

REMOTE_MODE=false
TEST_MODE=false
for arg in "$@"; do
    case "$arg" in
        --remote) REMOTE_MODE=true ;;
        --test) TEST_MODE=true ;;
    esac
done

if $REMOTE_MODE; then
    exec 3</dev/tty
else
    exec 3<&0
fi

SAVED_TTY=""
cleanup() {
    if [[ -n "$SAVED_TTY" ]] && [[ -t 3 ]]; then
        stty "$SAVED_TTY" <&3 2>/dev/null || true
    fi
    tput cnorm 2>/dev/null || true
}
trap cleanup EXIT

SESSIONS=()
SESSION_DETAILS=()

fetch_sessions() {
    SESSIONS=()
    SESSION_DETAILS=()
    if $TEST_MODE; then
        SESSIONS=("main" "dev" "debug")
        SESSION_DETAILS=("main: 2 windows (attached)" "dev: 1 window" "debug: 3 windows")
        return
    fi
    local raw
    raw=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null || true)
    while IFS='|' read -r name windows attached; do
        [[ -z "$name" ]] && continue
        SESSIONS+=("$name")
        local detail="${name}: ${windows} window"
        [[ "$windows" -ne 1 ]] && detail+="s"
        [[ "$attached" -gt 0 ]] && detail+=" (attached)"
        SESSION_DETAILS+=("$detail")
    done <<< "$raw"
}

MENU_ITEMS=()
build_menu() {
    MENU_ITEMS=()
    for detail in "${SESSION_DETAILS[@]}"; do
        MENU_ITEMS+=("$detail")
    done
    MENU_ITEMS+=("+ New session")
}

render_menu() {
    local selected=$1
    local total=${#MENU_ITEMS[@]}
    for ((i = 0; i < total; i++)); do
        tput el 2>/dev/null || true
        if [[ $i -eq $selected ]]; then
            printf "\e[7m > %s\e[0m\r\n" "${MENU_ITEMS[$i]}"
        else
            printf "   %s\r\n" "${MENU_ITEMS[$i]}"
        fi
    done
    tput el 2>/dev/null || true
    printf "\r\n"
    tput el 2>/dev/null || true
    if [[ $selected -lt ${#SESSIONS[@]} ]]; then
        printf "\e[2mEnter attach  d delete  r rename  n new  q quit\e[0m"
    else
        printf "\e[2mEnter new session  q quit\e[0m"
    fi
    local lines=$((total + 1))
    printf "\e[%dA\r" "$lines"
}

clear_menu() {
    local total=${#MENU_ITEMS[@]}
    local lines=$((total + 2))
    for ((i = 0; i < lines; i++)); do
        tput el 2>/dev/null || true
        printf "\r\n"
    done
    printf "\e[%dA" "$lines"
}

KEY_RESULT=""
read_key() {
    local key
    IFS= read -rsN1 key <&3 || true
    if [[ "$key" == $'\x1b' ]]; then
        local seq
        IFS= read -rsN1 -t 0.1 seq <&3 || true
        # Arrow keys arrive as ESC [ X (normal) or ESC O X (application cursor
        # key mode / DECCKM, which tmux leaves set on exit). Handle both.
        if [[ "$seq" == "[" || "$seq" == "O" ]]; then
            IFS= read -rsN1 -t 0.1 seq <&3 || true
            case "$seq" in
                A) KEY_RESULT="UP"; return ;;
                B) KEY_RESULT="DOWN"; return ;;
                3) IFS= read -rsN1 -t 0.1 _ <&3 || true
                   KEY_RESULT="OTHER"; return ;;
            esac
        fi
        KEY_RESULT="ESC"; return
    fi
    if [[ -z "$key" ]]; then
        KEY_RESULT="ENTER"; return
    fi
    local ord
    ord=$(printf '%d' "'$key" 2>/dev/null) || ord=0
    case $ord in
        10|13) KEY_RESULT="ENTER" ;;
        100|68) KEY_RESULT="DELETE" ;;
        114|82) KEY_RESULT="RENAME" ;;
        110|78) KEY_RESULT="NEW" ;;
        113|81) KEY_RESULT="QUIT" ;;
        *) KEY_RESULT="OTHER" ;;
    esac
}

confirm_delete() {
    local idx=$1
    local name="${SESSIONS[$idx]}"
    local total=${#MENU_ITEMS[@]}

    printf "\e[%dB" $((total + 1))
    tput el 2>/dev/null || true
    [[ -t 3 ]] && stty "$SAVED_TTY" <&3 2>/dev/null || true
    printf "Delete session \"%s\"? (y/n) " "$name"
    local answer
    IFS= read -rsn1 answer <&3
    [[ -t 3 ]] && stty raw -echo <&3 2>/dev/null || true

    printf "\r"
    tput el 2>/dev/null || true
    printf "\e[%dA" $((total + 1))

    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        if ! $TEST_MODE; then
            tmux kill-session -t "$name" 2>/dev/null || true
        fi
        fetch_sessions
        build_menu
        return 0
    fi
    return 1
}

# Prompt for a line of text below the menu, returning it in LINE_RESULT.
# $1 = prompt string, $2 = optional pre-filled/editable initial value.
# Returns 1 (and empty LINE_RESULT) on Esc or an empty submission.
#
# Reads char-by-char in raw mode (we stay in the menu's raw -echo mode rather
# than restoring cooked mode) so Esc is detectable — a cooked `read` can't see
# Esc, it's just a byte in the line. Handle Enter, Backspace, and Esc; echo
# printable chars ourselves since -echo is on.
LINE_RESULT=""
read_line_tty() {
    local prompt="$1" name="${2:-}" ch ord cancelled=false
    local total=${#MENU_ITEMS[@]}

    printf "\e[%dB" $((total + 1))
    tput el 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf "%s%s" "$prompt" "$name"

    while true; do
        IFS= read -rsN1 ch <&3 || true
        if [[ -z "$ch" ]]; then
            break   # NUL / EOF -> treat as Enter
        fi
        ord=$(printf '%d' "'$ch" 2>/dev/null) || ord=0
        case $ord in
            10|13) break ;;                          # Enter
            27)                                       # Esc -> cancel to menu
                # Drain any trailing bytes (e.g. an arrow key's ESC [ X).
                while IFS= read -rsN1 -t 0.05 _ <&3; do :; done
                cancelled=true
                break
                ;;
            127|8)                                    # Backspace / DEL
                if [[ -n "$name" ]]; then
                    name="${name%?}"
                    printf '\b \b'
                fi
                ;;
            *)
                name+="$ch"
                printf '%s' "$ch"
                ;;
        esac
    done

    tput civis 2>/dev/null || true

    # Erase the prompt line and return the cursor to the menu top so the
    # caller's render/clear lines up.
    printf "\r"
    tput el 2>/dev/null || true
    printf "\e[%dA" $((total + 1))

    if $cancelled || [[ -z "$name" ]]; then
        LINE_RESULT=""
        return 1
    fi
    LINE_RESULT="$name"
}

NEW_SESSION_NAME=""
prompt_new_session() {
    read_line_tty "Session name (Esc to cancel): " || return 1
    NEW_SESSION_NAME="$LINE_RESULT"
}

rename_session() {
    local idx=$1
    local old="${SESSIONS[$idx]}"
    read_line_tty "Rename \"$old\" to (Esc to cancel): " "$old" || return 1
    local new="$LINE_RESULT"
    [[ "$new" == "$old" ]] && return 1
    if ! $TEST_MODE; then
        tmux rename-session -t "$old" "$new" 2>/dev/null || true
    fi
    fetch_sessions
    build_menu
    return 0
}

attach_session() {
    local name="$1"
    if $TEST_MODE; then
        cleanup
        echo "[test] Would attach to session: $name"
        exit 0
    fi
    trap - EXIT
    [[ -n "$SAVED_TTY" ]] && [[ -t 3 ]] && stty "$SAVED_TTY" <&3 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf '\033]0;devterm: %s\007' "$name"
    exec tmux new-session -A -s "$name"
}

main() {
    fetch_sessions
    build_menu

    if [[ -t 3 ]]; then
        SAVED_TTY=$(stty -g <&3 2>/dev/null || true)
        stty raw -echo <&3 2>/dev/null || true
    fi

    # Force normal cursor-key mode (DECCKM reset) so arrows send ESC [ X, not
    # ESC O X. A prior tmux attach can leave the terminal in application mode.
    printf '\e[?1l'

    # Title the window while on the selector; attach_session upgrades this to
    # "devterm: <session>" on attach. Lets you tell same-icon devterm windows
    # apart in the dock fan-out / overview (see CreateDevTerm-linux.md).
    printf '\033]0;devterm\007'

    local selected=0
    local total=${#MENU_ITEMS[@]}

    tput civis 2>/dev/null || true

    printf "\r\n"
    render_menu $selected

    while true; do
        read_key
        total=${#MENU_ITEMS[@]}

        case "$KEY_RESULT" in
            UP)
                ((selected > 0)) && ((selected--)) || true
                render_menu $selected
                ;;
            DOWN)
                ((selected < total - 1)) && ((selected++)) || true
                render_menu $selected
                ;;
            ENTER)
                if [[ $selected -eq $((total - 1)) ]]; then
                    prompt_new_session || { render_menu $selected; continue; }
                    clear_menu
                    attach_session "$NEW_SESSION_NAME"
                else
                    clear_menu
                    attach_session "${SESSIONS[$selected]}"
                fi
                ;;
            NEW)
                prompt_new_session || { render_menu $selected; continue; }
                clear_menu
                attach_session "$NEW_SESSION_NAME"
                ;;
            RENAME)
                if [[ $selected -lt ${#SESSIONS[@]} ]]; then
                    rename_session $selected || true
                    render_menu $selected
                fi
                ;;
            DELETE)
                if [[ $selected -lt ${#SESSIONS[@]} ]]; then
                    if confirm_delete $selected; then
                        total=${#MENU_ITEMS[@]}
                        [[ $selected -ge $total ]] && selected=$((total - 1))
                        clear_menu
                    fi
                    render_menu $selected
                fi
                ;;
            QUIT|ESC)
                clear_menu
                printf "Cancelled.\r\n"
                exit 0
                ;;
            *)
                ;;
        esac
    done
}

main "$@"
ENDSCRIPT

# ---- Launch ----
if $TEST_MODE; then
    bash -c "$REMOTE_SCRIPT" -- --test
else
    # `base64 -w0` is GNU-only; BSD/macOS base64 rejects -w. Strip newlines
    # with tr instead so the encode is identical on both platforms.
    ENCODED=$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n')
    printf "Connecting to %s ...\n" "$HOST"
    # Route through the YubiKey type-ahead wrapper (see ssh-otp-connect.sh); it
    # forwards args verbatim via "$@", so the remote command below stays a single
    # untouched argument. Falls back to plain ssh when DEVSSH_NO_OTP=1 / no tty.
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "$SCRIPT_DIR/ssh-otp-connect.sh" -t -o "IdentityAgent=$SSH_AUTH_SOCK" "${SSH_USER}@${HOST}" \
        "echo $ENCODED | base64 -d > /tmp/.tmux_menu_\$\$ && bash /tmp/.tmux_menu_\$\$ --remote ; rm -f /tmp/.tmux_menu_\$\$"
fi
