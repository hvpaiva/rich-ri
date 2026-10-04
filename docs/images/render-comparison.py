#!/usr/bin/env python3
"""Render the README comparison from real RI output (requires Pillow and fontconfig)."""

import os
from pathlib import Path
import re
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/images/ri-vs-rich-ri.png"
COLUMNS = 58
SGR = re.compile(r"\x1b\[([\d;]*)m")
BACKGROUND, PANEL, FOREGROUND, MUTED = "#11111b", "#1e1e2e", "#cdd6f4", "#a6adc8"
PALETTE = [
    "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#89dceb", "#bac2de",
    "#9399b2", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#89dceb", "#ffffff",
]


def run(command, environment):
    return subprocess.check_output(command, cwd=ROOT, env=environment, text=True)


def capture():
    environment = {key: value for key, value in os.environ.items() if not key.startswith("RICH_RI_")}
    environment.update(RI="", RI_PAGER="cat", PAGER="cat", NO_COLOR="", TERM="xterm-256color", BAT_THEME="ansi")
    # Shell highlighting is part of this example, so require bat instead of silently falling back.
    bat_version = run(["bat", "--version"], environment).splitlines()[0]
    ruby_versions = run(
        ["bundle", "exec", "ruby", "-rrdoc", "-e", 'print "Ruby #{RUBY_VERSION} / RDoc #{RDoc::VERSION}"'],
        environment,
    )
    commands = {
        "ri -f ansi": ["bundle", "exec", "ri", "--no-pager", "-f", "ansi", f"--width={COLUMNS}", "ARGF"],
        "rich-ri": ["bundle", "exec", "ruby", "-Ilib", "exe/rich-ri", "--no-config", "--no-pager",
                    "--color=always", f"--width={COLUMNS}", "ARGF"],
    }
    directory = Path(tempfile.mkdtemp(prefix="rich-ri-comparison-"))
    excerpts = {}
    for name, command in commands.items():
        raw = run(command, environment)
        (directory / f"{name}.full.ansi").write_text(raw)
        lines = raw.splitlines()
        headings = [re.sub(r"^={1,6} ", "", SGR.sub("", line)) for line in lines]
        start, end = headings.index("Reading"), headings.index("About the Examples")
        excerpt = "\n".join(lines[start:end]).rstrip() + "\n"
        assert "\x1b[" in excerpt, f"Missing colors in {name}"
        (directory / f"{name}.ansi").write_text(excerpt)
        excerpts[name] = excerpt
    print(f"Raw captures: {directory}")
    return excerpts, ruby_versions, bat_version


def default_style():
    return dict(fg=FOREGROUND, bg=PANEL, bold=False, italic=False, underline=False, reverse=False)


def terminal_rows(raw):
    """Interpret SGR attributes, including RI's reverse video, then soft-wrap like a terminal."""
    style = default_style()
    rows = []
    for line in raw.splitlines():
        cells = []
        for token in re.findall(r"\x1b\[[\d;]*m|.", line):
            match = SGR.fullmatch(token)
            if not match:
                # This English excerpt is ASCII; fail if it ever needs wide-cell handling.
                assert " " <= token <= "~", f"Unexpected character: {token!r}"
                cells.append((token, style.copy()))
                continue
            for code in map(lambda value: int(value or "0"), match[1].split(";")):
                if code == 0:
                    style = default_style()
                elif code in (1, 3, 4, 7, 22, 23, 24, 27):
                    key = {1: "bold", 3: "italic", 4: "underline", 7: "reverse",
                           22: "bold", 23: "italic", 24: "underline", 27: "reverse"}[code]
                    style[key] = code < 20
                elif code == 39:
                    style["fg"] = FOREGROUND
                elif code == 49:
                    style["bg"] = PANEL
                elif 30 <= code <= 37:
                    style["fg"] = PALETTE[code - 30]
                elif 90 <= code <= 97:
                    style["fg"] = PALETTE[code - 90 + 8]
                else:
                    raise ValueError(f"Unsupported SGR {code}; update the renderer before using this capture")
        rows.extend([cells[index:index + COLUMNS] for index in range(0, len(cells), COLUMNS)] or [[]])
    return rows


def font(pattern, size):
    path = subprocess.check_output(["fc-match", "-f", "%{file}", pattern], text=True)
    return ImageFont.truetype(path, size)


def render(excerpts, ruby_versions, bat_version):
    fonts = {
        (False, False): font("monospace:style=Regular", 22),
        (True, False): font("monospace:style=Bold", 22),
        (False, True): font("monospace:style=Italic", 22),
        (True, True): font("monospace:style=Bold Italic", 22),
    }
    normal = fonts[False, False]
    label, small = font("sans:style=Bold", 28), font("sans:style=Regular", 21)
    cell, line_height = normal.getlength("M"), 32
    padding, gap, margin = 26, 24, 30
    panel_width = round(COLUMNS * cell + 2 * padding)
    captures = {name: terminal_rows(raw) for name, raw in excerpts.items()}
    content_top = 164
    height = content_top + max(map(len, captures.values())) * line_height + 90
    image = Image.new("RGB", (2 * margin + 2 * panel_width + gap, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    commands = {
        "ri -f ansi": f"$ ri -f ansi --no-pager --width={COLUMNS} ARGF",
        "rich-ri": f"$ rich-ri --no-pager --color=always --width={COLUMNS} ARGF",
    }
    for index, (name, rows) in enumerate(captures.items()):
        left = margin + index * (panel_width + gap)
        draw.rounded_rectangle((left, 24, left + panel_width, height - 64), radius=15,
                               fill=PANEL, outline="#313244", width=1)
        draw.text((left + padding, 40), name, font=label, fill=FOREGROUND)
        detail = "Built-in ANSI formatter" if index == 0 else "Ruby + shell syntax highlighting"
        detail_width = draw.textlength(detail, font=small)
        draw.text((left + panel_width - padding - detail_width, 47), detail, font=small, fill=MUTED)
        draw.line((left, 88, left + panel_width, 88), fill="#313244")
        draw.text((left + padding, 111), commands[name], font=normal, fill=FOREGROUND)
        for row_index, row in enumerate(rows):
            y = content_top + row_index * line_height
            for column, (char, style) in enumerate(row):
                x = left + padding + column * cell
                fg, bg = style["fg"], style["bg"]
                if style["reverse"]:
                    fg, bg = bg, fg
                if bg != PANEL:
                    draw.rectangle((x, y, x + cell, y + line_height), fill=bg)
                face = fonts[style["bold"], style["italic"]]
                draw.text((x, y + 24), char, font=face, fill=fg, anchor="ls")
                if style["underline"]:
                    draw.line((x, y + 27, x + cell, y + 27), fill=fg)
    caption = f"Same ARGF excerpt, {COLUMNS} columns and terminal palette · {ruby_versions} · {bat_version.split(' (')[0]}"
    draw.text((margin, height - 42), caption, font=small, fill=MUTED)
    image.save(OUTPUT, optimize=True)
    print(f"{OUTPUT}: {image.width}x{image.height}, {OUTPUT.stat().st_size} bytes")


if __name__ == "__main__":
    render(*capture())
