# bash completion for rich-ri; requires bash-completion 2.x.
# shellcheck shell=bash

_rich_ri() {
    # _init_completion assigns prev through Bash's dynamic scope.
    # shellcheck disable=SC2034
    local cur prev words cword value _description directive="" typed=${2-}
    local -a names=()
    COMPREPLY=()
    _init_completion -n ':=' || return
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

complete -F _rich_ri rich-ri
