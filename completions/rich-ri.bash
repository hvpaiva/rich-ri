# bash completion for rich-ri; requires bash-completion 2.x.
# shellcheck shell=bash

_rich_ri() {
  # _init_completion assigns prev through Bash's dynamic scope.
  # shellcheck disable=SC2034
  local cur prev words cword value _description
  COMPREPLY=()
  _init_completion -n ':=' || return
  while IFS=$'\t' read -r value _description; do
    [[ -n $value ]] && COMPREPLY+=("$value")
  done < <(command rich-ri --complete --shell=bash "${words[@]:1:cword}" 2>/dev/null)
  if ((${#COMPREPLY[@]} == 1)) && [[ ${COMPREPLY[0]} == *[:.#/=] ]]; then
    compopt -o nospace 2>/dev/null || :
  fi
  [[ $cur == *:* ]] && __ltrim_colon_completions "$cur"
  if [[ $cur == *=* && $COMP_WORDBREAKS == *'='* ]]; then
    COMPREPLY=("${COMPREPLY[@]#*=}")
  fi
  return 0
}

complete -o filenames -F _rich_ri rich-ri
