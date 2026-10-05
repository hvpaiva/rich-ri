# Troubleshooting

## A page is missing

Check `rich-ri --list` for known classes and `rich-ri --list-doc-dirs` for the
directories being searched. Try `ri NAME` with the original reader as well.
If you use an alias, `command ri NAME` bypasses it in Bash and Zsh.

For a gem installed without documentation, run `gem rdoc GEM_NAME --ri`.
For Ruby's core classes, install the documentation package supplied by your Ruby
manager or operating system. Switch to the intended Ruby before generating or
reading documentation: each installation has its own stores.

See [documentation sources](usage.md#documentation-sources-and-missing-pages)
to read documentation from a project directory.

## An RI cache has an incompatible format

RDoc uses different serialized markup representations on Ruby 3 and Ruby 4.
Keep documentation with the Ruby installation that generated it. Regenerate gem
documentation with `gem rdoc GEM_NAME --ri` under the Ruby you are using now.

For core documentation, obtain the source for that Ruby version, then generate a
new RI store with the current RDoc. For example, from the Ruby source directory:

```sh
rdoc --ri --op doc/ri
rich-ri --no-standard-docs --doc-dir doc/ri Array
```

Use [doc_dirs](configuration.md#file-keys) to keep using the new store. Do not
copy a cache from another Ruby installation as a substitute for regeneration.

## Colors are missing or hard to read

Colors are enabled automatically on a terminal. `NO_COLOR`, `TERM=dumb` and
redirected output disable automatic colors. Try `rich-ri --color=always NAME`
to force them, or `rich-ri --no-color NAME` for plain output.

The default theme uses the terminal's palette. Adjust a role such as
`--style='comment=bright_black'`, or select `--theme=light` or `--theme=dark`.
[Themes and styles](configuration.md#themes-and-styles) describes persistent settings.

Ruby highlighting is built in. Shell examples and other tagged languages need
bat on `PATH`; confirm it with `bat --version`. If bat fails or cannot safely
highlight an example, that example stays plain. A failure disables bat for the
rest of the page. `--shell-theme` and `--bat-theme` must name an installed bat
theme; list them with `bat --list-themes`.

## The pager behaves differently

Try `rich-ri --no-pager NAME` to isolate the reader from the pager.
`RI_PAGER` takes precedence over `PAGER`; a configured pager command and
`--pager-command` can also select it. Check the effective settings with
`rich-ri --show-config`. For less, rich-ri adds `-R` so ANSI colors are displayed.

## An optional RDoc mode cannot start

`--server` needs the `webrick` gem; `--profile` needs the `profile` gem. Install
the named gem with the active Ruby, then repeat the command. For example,
`gem install webrick` enables the web server. With `bundle exec`, include the
gem in the current Gemfile as well.

These gems are not required for terminal lookup or completion. See
[optional RDoc modes](usage.md#optional-rdoc-modes) for their behavior.

## Configuration prevents startup

`rich-ri --config-path` prints the selected file. `--no-config` skips that file;
environment variables still apply. Help and version output remain available
even when the file contains invalid YAML or settings.

See [configuration troubleshooting](configuration.md#troubleshooting) for
precedence, YAML types and path handling.

## Tab completion is missing

Follow the setup for your shell in [shell completion](shell-completion.md).
After changing a shell startup file, open a new shell or load the file again.
For an alias, include the alias setup from that guide.

If options complete but documentation names do not, check `--show-config` and
`--list-doc-dirs`. Invalid settings or an unreadable RI store prevent name
discovery. Bash and Fish completion scripts should be reinstalled after an upgrade.

## Report a problem

Include the command, expected result, actual result and a small document that
reproduces it. Provide `rich-ri --version`, `ruby --version`, your operating
system, shell and terminal, and the output of `gem list --local rdoc prism reline`.
For shell highlighting, include `bat --version` too.

Review any configuration output before sharing it; pager arguments and file
paths can contain private information. Open a [bug report](https://github.com/hvpaiva/rich-ri/issues/new?template=bug.yml).
Use the [private security channel](../SECURITY.md) for vulnerabilities.
