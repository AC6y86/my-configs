#!/bin/bash
set -euo pipefail

TEST_MODE=false
[[ "${1:-}" == "--test" ]] && TEST_MODE=true

if ! $TEST_MODE && [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "ERROR: SSH_AUTH_SOCK not set. Run 'source ~/.bashrc' or open a new terminal." >&2
    exit 1
fi

SSH_USER="joepaley"
HOST="devvm7002.scu0.facebook.com"

# ---- Menu script: runs on the devvm (or locally in test mode) ----
REMOTE_SCRIPT=$(cat <<'ENDSCRIPT'
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
        printf "\e[2mEnter attach  d delete  n new  q quit\e[0m"
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
        if [[ "$seq" == "[" ]]; then
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

NEW_SESSION_NAME=""
prompt_new_session() {
    local total=${#MENU_ITEMS[@]}

    printf "\e[%dB" $((total + 1))
    tput el 2>/dev/null || true
    [[ -t 3 ]] && stty "$SAVED_TTY" <&3 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf "Session name: "
    local name
    read -r name <&3

    if [[ -z "$name" ]]; then
        printf "\e[1A"
        tput el 2>/dev/null || true
        printf "\e[%dA" $((total + 1))
        tput civis 2>/dev/null || true
        [[ -t 3 ]] && stty raw -echo <&3 2>/dev/null || true
        return 1
    fi

    NEW_SESSION_NAME="$name"
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
    exec tmux new-session -A -s "$name"
}

main() {
    fetch_sessions
    build_menu

    if [[ -t 3 ]]; then
        SAVED_TTY=$(stty -g <&3 2>/dev/null || true)
        stty raw -echo <&3 2>/dev/null || true
    fi

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
)

# ---- Launch ----
if $TEST_MODE; then
    bash -c "$REMOTE_SCRIPT" -- --test
else
    ENCODED=$(printf '%s' "$REMOTE_SCRIPT" | base64 -w0)
    printf "Connecting to %s ...\n" "$HOST"
    exec ssh -t -o "IdentityAgent=$SSH_AUTH_SOCK" "${SSH_USER}@${HOST}" \
        "echo $ENCODED | base64 -d > /tmp/.tmux_menu_\$\$ && bash /tmp/.tmux_menu_\$\$ --remote ; rm -f /tmp/.tmux_menu_\$\$"
fi
