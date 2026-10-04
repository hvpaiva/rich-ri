#compdef rich-ri

_rich_ri() {
  local value description
  local -a values descriptions
  while IFS=$'\t' read -r value description; do
    [[ -n $value ]] || continue
    values+=("$value")
    descriptions+=("$value${description:+ -- $description}")
  done < <(command rich-ri --complete "${words[@]:1:$((CURRENT - 1))}" 2>/dev/null)
  if (( ${#values} == 1 )) && [[ ${values[1]} == *[:.#/=] ]]; then
    compadd -S '' -d descriptions -- "${values[@]}"
  else
    compadd -d descriptions -- "${values[@]}"
  fi
}

compdef _rich_ri rich-ri
