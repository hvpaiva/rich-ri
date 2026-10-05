#compdef rich-ri
# zsh completion for rich-ri
#
# Install it as _rich-ri in a directory of your fpath, where compinit finds it
# and loads it the first time it is needed:
#
#   mkdir -p ~/.zfunc && rich-ri --completion=zsh > ~/.zfunc/_rich-ri
#
# with "fpath+=(~/.zfunc)" before compinit in ~/.zshrc. Or load it there, after
# compinit, with: source <(rich-ri --completion=zsh)

_rich-ri() {
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

# Loaded from fpath, this file is the body of the function on its first call.
if [[ $zsh_eval_context[-1] == loadautofunc ]]; then
  _rich-ri "$@"
else
  compdef _rich-ri rich-ri
fi
