#compdef rich-ri

_rich_ri() {
  local value description directive=""
  local -a values descriptions
  while IFS=$'\t' read -r value description; do
    if [[ $value == :* ]]; then
      directive=${value#:}
    elif [[ -n $value ]]; then
      values+=("$value")
      descriptions+=("$value${description:+ -- $description}")
    fi
  done < <(command rich-ri --complete --shell=zsh "${words[@]:1:$((CURRENT - 1))}" 2>/dev/null)
  case $directive in
    # The shell completes a path by itself, after "--option=" as well.
    files) compset -P '--[^=]#='; _files ;;
    directories) compset -P '--[^=]#='; _files -/ ;;
    nospace) compadd -S '' -d descriptions -- "${values[@]}" ;;
    *) compadd -d descriptions -- "${values[@]}" ;;
  esac
}

compdef _rich_ri rich-ri
