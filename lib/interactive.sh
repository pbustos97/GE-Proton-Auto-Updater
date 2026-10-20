#!/bin/bash

# Interactive helpers for the GE Proton management scripts
# (ge_proton_install.sh and ge_proton_uninstall.sh).
#
# Deliberately NOT included by ge_proton_update.sh: this library is only for
# manual maintenance work, never for the automated systemd updater.
# Requires lib/common.sh to be sourced first (shares log() and script_id).

# Returns success when both stdin and stdout are a usable terminal.
# GE_PROTON_FORCE_TTY=1 pretends a TTY is attached; intended for automated
# tests where interactive answers are supplied through a pipe.
interactive_ok() {
    if [[ ${GE_PROTON_FORCE_TTY:-0} == 1 ]]; then
        return 0
    fi
    [[ -t 0 && -t 1 ]]
}

# Ask a yes/no question. Defaults to "no" on empty answer, EOF, or when not
# running in a terminal. Re-prompts on invalid input.
confirm() {
    local reply
    if ! interactive_ok; then
        log "Not running interactively; refusing to confirm"
        return 1
    fi
    while :; do
        read -r -p "$1 [y/N]: " reply || return 1
        reply=${reply%$'\r'}
        case $reply in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO|"") return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# Multi-select picker.
#
#   multi_select "prompt" "line 1" "line 2" ...
#
# Uses fzf when available and a TTY is attached; otherwise falls back to a
# numbered list with a token prompt. Accepted token forms in the numbered
# prompt: N (choose), N-M (range), ^N/^N-M (deselect), a (choose all).
# An empty answer or ESC cancels the selection.
#
# Output: global array PICKED with the 1-based line indices of the
# selection, in ascending order; PICKED stays empty when nothing is chosen.
# Returns non-zero when the selection is aborted or input is unavailable.
multi_select() {
    local prompt=$1
    shift

    PICKED=()

    local count=$#
    if (( count == 0 )); then
        log "Nothing to choose from"
        return 1
    fi

    # Lines guaranteed to start with "<index>) " so that every selection
    # maps back to the caller's data by index
    local -a lines=()
    local i
    for (( i = 1; i <= count; i++ )); do
        lines+=( "$i) $1" )
        shift
    done

    # fzf path
    if interactive_ok && command -v fzf >/dev/null 2>&1; then
        local chosenRaw
        if ! chosenRaw=$(printf '%s\n' "${lines[@]}" | \
            fzf --multi --reverse --height=80% --no-sort \
                --prompt="$prompt" \
                --header="TAB/SHIFT-TAB to select, ENTER to confirm, ESC to cancel" 2>/dev/null)
        then
            return 1  # canceled with ESC
        fi
        local line
        while IFS= read -r line; do
            if [[ $line =~ ^([0-9]+)\) ]]; then
                PICKED+=( "${BASH_REMATCH[1]}" )
            fi
        done <<<"$chosenRaw"
        # fzf returns selections in selection order; re-number them ascending
        if (( ${#PICKED[@]} > 0 )); then
            mapfile -t PICKED < <(printf '%s\n' "${PICKED[@]}" | sort -n -u)
            return 0
        fi
        return 1  # accepted with nothing marked -> treat as cancel
    fi

    # Numbered fallback: keep prompting until a valid selection is made
    if ! interactive_ok; then
        log "Requires an interactive terminal"
        return 1
    fi
    printf '%s\n' "${lines[@]}"
    local reply token ok index from to
    while :; do
        if ! read -e -r -p "Select (space-separated, e.g. 1 3 4-6, 'a' for all, Enter to cancel): " reply; then
            return 1  # EOF
        fi
        reply=${reply%$'\r'}
        if [[ -z $reply ]]; then
            return 1  # canceled
        fi
        local -A selected=()
        ok=1
        for token in $reply; do
            if [[ $token == a || $token == all ]]; then
                for (( index = 1; index <= count; index++ )); do
                    selected[$index]=1
                done
            elif [[ $token =~ ^\^([0-9]+)(-([0-9]+))?$ ]]; then
                from=${BASH_REMATCH[1]}
                to=${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}
                if (( from < 1 || to > count || from > to )); then
                    echo "Out of range: $token"
                    ok=0
                else
                    for (( index = from; index <= to; index++ )); do
                        unset "selected[$index]"
                    done
                fi
            elif [[ $token =~ ^([0-9]+)(-([0-9]+))?$ ]]; then
                from=${BASH_REMATCH[1]}
                to=${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}
                if (( from < 1 || to > count || from > to )); then
                    echo "Out of range: $token"
                    ok=0
                else
                    for (( index = from; index <= to; index++ )); do
                        selected[$index]=1
                    done
                fi
            else
                echo "Unrecognized: $token"
                ok=0
            fi
            if (( ok == 0 )); then
                break
            fi
        done
        if (( ok == 1 )); then
            for (( i = 1; i <= count; i++ )); do
                if [[ -n ${selected[$i]:-} ]]; then
                    PICKED+=( "$i" )
                fi
            done
            if (( ${#PICKED[@]} > 0 )); then
                return 0
            fi
            echo "Nothing selected; try again or press Enter to cancel."
        fi
    done
}
