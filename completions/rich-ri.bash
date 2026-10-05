# bash completion for rich-ri
#
# bash-completion is used when it is loaded and is not required.
#
# shellcheck shell=bash

# The function names and the words, cur and out variables are the ones of the
# scripts cobra generates. ble.sh knows that shape: it runs the command without
# blocking the line and shows the descriptions in its own menu.
__start_rich_ri() {
    # prev is assigned by the initializers of bash-completion; it stays local.
    # shellcheck disable=SC2034
    local cur prev words cword
    if declare -F _comp_initialize >/dev/null 2>&1; then
        _comp_initialize -n ':=' -- "$@" || return
    elif declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -n ':=' || return
    else
        __rich_ri_words || return
    fi
    # The first word may be an alias or a function. ble.sh runs this one.
    words[0]=__rich_ri_complete

    local out directive typed=${2-}
    __rich_ri_get_completion_results
    COMPREPLY=()
    # The candidates are names, however the function was registered.
    compopt +o filenames 2>/dev/null
    case $directive in
        # The shell completes a path by itself: "~", variables and quotes are its own.
        files) compopt -o default 2>/dev/null ;;
        directories) compopt -o dirnames 2>/dev/null ;;
        *)
            [[ $directive == nospace ]] && compopt -o nospace 2>/dev/null
            # ble.sh adds file names of its own to an answer without candidates
            # and takes a candidate that also names a directory for that directory.
            [[ -n ${BLE_ATTACHED-} ]] && compopt -o ble/no-default -o ble/no-mark-directories 2>/dev/null
            [[ -n $out ]] && __rich_ri_handle_completion_types
            ;;
    esac
    return 0
}

__rich_ri_complete() {
    command rich-ri --complete --shell=bash "$@"
}

# Leaves the candidate lines in out and the last line, without its colon, in
# directive. A line keeps its tab only when a description follows it.
__rich_ri_get_completion_results() {
    out=$("${words[0]}" "${words[@]:1:cword-1}" "$cur" 2>/dev/null)
    directive=${out##*$'\n':}
    [[ $out == :* ]] && directive=${out#:}
    out=${out%$'\n'*}
    [[ $out == :* ]] && out=""
    out=${out//$'\t\n'/$'\n'} out=${out%$'\t'}
    return 0
}

# out holds the lines as one string or, after ble.sh took the described ones
# for its menu, the others as an array.
__rich_ri_handle_completion_types() {
    local chunk line
    local -a names=() notes=()
    for chunk in "${out[@]}"; do
        while IFS= read -r line; do
            [[ -n $line ]] || continue
            names+=("${line%%$'\t'*}")
            if [[ $line == *$'\t'* ]]; then notes+=("${line#*$'\t'}"); else notes+=(""); fi
        done <<<"$chunk"
    done

    # Only the end of the word is replaced when it holds ":" or "=", where
    # readline breaks words, or follows an open quote: head is what stays.
    local head quote REPLY
    __rich_ri_dequote "${cur%"$typed"}"
    head=$REPLY
    # ble.sh breaks the word itself, says what it keeps and quotes what it inserts.
    [[ -n ${BLE_ATTACHED-} ]] && head=${progcomp_prefix-$head} quote=ble

    local i name reply
    local -a replies=()
    for i in "${!names[@]}"; do
        name=${names[i]}
        if [[ $name != "$head"* ]]; then
            unset "names[i]" "notes[i]"
            continue
        fi
        reply=${name#"$head"}
        case $quote in
            ble) ;;
            "'") reply=${reply//\'/\'\\\'\'} ;;
            '"') reply=${reply//\\/\\\\} reply=${reply//\"/\\\"} reply=${reply//\$/\\\$} reply=${reply//\`/\\\`} ;;
            *) [[ -n $reply ]] && printf -v reply %q "$reply" ;;
        esac
        replies[i]=$reply
    done

    # A list is asked for by the second Tab (63) or shown along with what is
    # inserted (33 and 64). Only the first inserts nothing, so it can show the
    # names whole; all of them can carry the descriptions.
    case ${COMP_TYPE-}:${#replies[@]} in
        *:[01]) COMPREPLY=("${replies[@]}") ;;
        63:*) __rich_ri_describe "${names[@]}" ;;
        33:* | 64:*) __rich_ri_describe "${replies[@]}" ;;
        *) COMPREPLY=("${replies[@]}") ;;
    esac
}

# Replies with the given texts, each followed by its description in a column.
__rich_ri_describe() {
    local text note line width=0 room
    for text in "$@"; do (( ${#text} > width )) && width=${#text}; done
    room=$(( ${COLUMNS:-80} - width - 4 ))
    for note in "${notes[@]}"; do
        text=$1
        shift
        if [[ -z $note ]] || (( room < 8 )); then
            COMPREPLY+=("$text")
            continue
        fi
        (( ${#note} > room )) && note="${note:0:room-3}..."
        printf -v line '%-*s  (%s)' "$width" "$text" "$note"
        COMPREPLY+=("$line")
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

# The name this function had; an alias registered with it keeps working.
_rich_ri() {
    __start_rich_ri "$@"
}

complete -F __start_rich_ri rich-ri
