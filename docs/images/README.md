# README comparison

`ri-vs-rich-ri.png` compares the original `ri -f ansi` formatter with rich-ri's
default terminal theme. Both panels show the same contiguous excerpt of the
installed `ARGF` documentation, from **Reading** through **Simplest Case**.

The renderer captures both commands with the project's Bundler environment and
the same 58-column width, then displays their actual ANSI output using the same
dark terminal palette and monospace font. It preserves bold, italic,
underline and reverse-video attributes, including the original formatter's
inline-code styling. Long code and output lines soft-wrap at the panel width.
The content is not rewritten or aligned by adding or removing document lines.

To refresh the image, install the bundle, Ruby core RI documentation, bat,
Python 3, Pillow, fontconfig and a monospace font with bold and italic faces.
The Python tools and fonts are only needed to regenerate this image.

```sh
python3 docs/images/render-comparison.py
```

The script clears reader configuration overrides, requires bat for the shell
example, and saves the raw captures in a temporary directory printed at the end.
Its footer records the Ruby, RDoc and bat versions. Review the PNG before
committing it; documentation text can change between Ruby versions.
