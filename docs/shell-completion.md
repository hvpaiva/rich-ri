# Shell completion

Completion reads the active Ruby's RI stores, including sources selected in your
configuration file, `RI` or `--doc-dir`. It makes no network requests. It suggests
installed classes, methods, pages, options, theme names and style roles, with
descriptions where available. Invalid configuration or unavailable stores prevent
documentation-name suggestions; options and theme values remain available. Run
`rich-ri --show-config` to diagnose configuration errors.

## Bash

Load bash-completion 2.x in your shell, then install the lazy-loaded script:

```sh
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
rich-ri --completion=bash > "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/rich-ri"
```

To load it in the current shell, run `source <(rich-ri --completion=bash)`.

## Zsh

After `autoload -Uz compinit && compinit` in your `.zshrc`, add:

```zsh
source <(rich-ri --completion=zsh)
```

## Fish

```fish
mkdir -p "$__fish_config_dir/completions"
rich-ri --completion=fish > "$__fish_config_dir/completions/rich-ri.fish"
```

## Use the short name ri

For Bash, add these lines after loading bash-completion:

```bash
alias ri='rich-ri'
source <(rich-ri --completion=bash)
complete -o filenames -F _rich_ri ri
```

For Zsh, add `alias ri='rich-ri'` after the completion setup. Zsh expands aliases
for completion by default. In Fish, use `alias ri rich-ri` in your configuration;
Fish aliases inherit completions from the wrapped command.

Bash and Fish install a copy of the script; repeat the installation after upgrading
rich-ri. The Zsh setup loads the current script when a new shell starts.
