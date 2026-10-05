# bash completion for rich-ri; requires bash-completion 2.x.
# shellcheck shell=bash

_rich_ri() {
  # _init_completion assigns prev through Bash's dynamic scope.
  # shellcheck disable=SC2034
  local cur prev words cword value _description directive=""
  COMPREPLY=()
  _init_completion -n ':=' || return
  while IFS=$'\t' read -r value _description; do
    if [[ $value == :* ]]; then
      directive=${value#:}
    elif [[ -n $value ]]; then
      COMPREPLY+=("$value")
    fi
  done < <(command rich-ri --complete --shell=bash "${words[@]:1:cword}" 2>/dev/null)
  case $directive in
    # The shell completes a path by itself: "~", variables and quotes are its own.
    files) compopt -o default 2>/dev/null; return 0 ;;
    directories) compopt -o dirnames 2>/dev/null; return 0 ;;
    nospace) compopt -o nospace 2>/dev/null ;;
  esac
  [[ $cur == *:* ]] && __ltrim_colon_completions "$cur"
  if [[ $cur == *=* && $COMP_WORDBREAKS == *'='* ]]; then
    COMPREPLY=("${COMPREPLY[@]#*=}")
  fi
  return 0
}

complete -o filenames -F _rich_ri rich-ri
