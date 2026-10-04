# README comparison

`ri-vs-rich-ri.png` compares the original `ri -f ansi` formatter with rich-ri's
default terminal theme. Both panels show the complete installed `Object#then`
documentation, from the first line to the last. Its Ruby examples include method
chains, blocks, strings, constants and symbols.

The renderer captures both commands with the project's Bundler environment and
the same 58-column width, then displays their actual ANSI output using the same
dark terminal palette and monospace font. It preserves bold, italic,
underline and reverse-video attributes, including the original formatter's
inline-code styling. Long code and output lines soft-wrap at the panel width.
Every output line is included. The displayed commands show normal interactive
usage; capture adds `--no-pager --width=58` to both, and
`--no-config --color=always` to rich-ri.

To refresh the image, install the bundle, Ruby core RI documentation,
ImageMagick with SVG support and a monospace font with bold and italic faces.
The script uses Ruby's standard libraries to capture the output and generate
an SVG, then ImageMagick to convert it to PNG.

```sh
ruby docs/images/render_comparison.rb
```

The script clears reader configuration overrides and saves the full raw captures
and SVG in a temporary directory printed at the end. Its footer records the Ruby
and RDoc versions. Review the PNG before committing it; documentation text can
change between Ruby versions.
