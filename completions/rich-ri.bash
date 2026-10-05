# bash completion for rich-ri
#
# bash-completion is used when it is loaded and is not required.
#
# shellcheck shell=bash

_rich_ri() {
    # prev is assigned by the initializers of bash-completion; it stays local.
    # shellcheck disable=SC2034
    local cur prev words cword value _description directive="" typed=${2-}
    local -a names=()
    COMPREPLY=()
    if declare -F _comp_initialize >/dev/null 2>&1; then
        _comp_initialize -n ':=' -- "$@" || return
    elif declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -n ':=' || return
    else
        __rich_ri_words || return
    fi
    while IFS=$'\t' read -r value _description; do
        if [[ $value == :* ]]; then
            directive=${value#:}
        elif [[ -n $value ]]; then
            names+=("$value")
        fi
    done < <(command rich-ri --complete --shell=bash "${words[@]:1:cword-1}" "$cur" 2>/dev/null)
    # The candidates are names, however the function was registered.
    compopt +o filenames 2>/dev/null
    case $directive in
        # The shell completes a path by itself: "~", variables and quotes are its own.
        files) compopt -o default 2>/dev/null ;;
        directories) compopt -o dirnames 2>/dev/null ;;
        *)
            [[ $directive == nospace ]] && compopt -o nospace 2>/dev/null
            __rich_ri_reply "${names[@]}"
            ;;
    esac
    return 0
}

# Replies with the end of each name that readline is to replace, quoted as
# the word needs it where it stands.
__rich_ri_reply() {
    # Only the end of the word is replaced when it holds ":" or "=", where
    # readline breaks words, or follows an open quote: head is what stays.
    local head quote REPLY
    __rich_ri_dequote "${cur%"$typed"}"
    head=$REPLY

    local name reply
    for name in "$@"; do
        [[ $name == "$head"* ]] || continue
        reply=${name#"$head"}
        case $quote in
            "'") reply=${reply//\'/\'\\\'\'} ;;
            '"') reply=${reply//\\/\\\\} reply=${reply//\"/\\\"} reply=${reply//\$/\\\$} reply=${reply//\`/\\\`} ;;
            *) [[ -n $reply ]] && printf -v reply %q "$reply" ;;
        esac
        COMPREPLY+=("$reply")
    done
}

# Leaves in REPLY the text as the command would receive it, without quotes and
# backslashes and with nothing in it evaluated, and in quote the quote that is
# still open at its end.
__rich_ri_dequote() {
    local text=$1 char
    REPLY="" quote=""
    while [[ -n $text ]]; do
        char=${text:0:1} text=${text:1}
        case $quote$char in
            "'" | '"') quote=$char ;;
            "''" | '""') quote="" ;;
            \\) REPLY+=${text:0:1} text=${text:1} ;;
            \"\\)
                [[ ${text:0:1} == [\"\\\$\`] ]] && char=${text:0:1} text=${text:1}
                REPLY+=$char
                ;;
            *) REPLY+=$char ;;
        esac
    done
}

# Without bash-completion: bash breaks a word at each ":" and "=", so the
# pieces that no blank separates on the line are put together again in words,
# with cword for the one under the cursor and cur for it up to the cursor.
__rich_ri_words() {
    # After a redirection the word is the name of a file.
    if [[ ${COMP_WORDS[COMP_CWORD - 1]-} == *[\<\>]* ]]; then
        compopt -o default 2>/dev/null
        return 1
    fi
    local line=$COMP_LINE rest piece last="" i past
    words=() cword=0 cur=""
    for i in "${!COMP_WORDS[@]}"; do
        piece=${COMP_WORDS[i]}
        rest=${line#"${line%%[![:blank:]]*}"}
        if (( i > 0 )) && [[ $rest == "$line" && ($piece != *[!:=]* || $last != *[!:=]*) ]]; then
            words[${#words[@]} - 1]+=$piece
        else
            words+=("$piece")
        fi
        line=${rest#"$piece"} last=$piece
        (( i == COMP_CWORD )) || continue
        cword=$(( ${#words[@]} - 1 )) cur=${words[cword]}
        past=$(( ${#COMP_LINE} - ${#line} - COMP_POINT ))
        (( past > 0 && past <= ${#cur} )) && cur=${cur:0:${#cur} - past}
    done
    return 0
}

complete -F _rich_ri rich-ri
