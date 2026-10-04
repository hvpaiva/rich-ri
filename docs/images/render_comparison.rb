# frozen_string_literal: true

require "cgi"
require "open3"
require "tmpdir"

# Capture real output and draw its ANSI attributes into an SVG for ImageMagick.
class ReadmeComparison
  ROOT = File.expand_path("../..", __dir__)
  OUTPUT = File.join(__dir__, "ri-vs-rich-ri.png")
  QUERY = "Object#then"
  COLUMNS = 58
  SGR = /\e\[([\d;]*)m/
  BACKGROUND = "#11111b"
  PANEL = "#1e1e2e"
  FOREGROUND = "#cdd6f4"
  MUTED = "#a6adc8"
  PALETTE = %w[
    #45475a #f38ba8 #a6e3a1 #f9e2af #89b4fa #cba6f7 #89dceb #bac2de
    #9399b2 #f38ba8 #a6e3a1 #f9e2af #89b4fa #cba6f7 #89dceb #ffffff
  ].freeze
  ATTRIBUTES = { 1 => :bold, 3 => :italic, 4 => :underline, 7 => :reverse,
                 22 => :bold, 23 => :italic, 24 => :underline, 27 => :reverse }.freeze
  CELL = 14
  LINE_HEIGHT = 32
  PANEL_WIDTH = (COLUMNS * CELL) + 52

  def initialize
    @environment = ENV.keys.grep(/\ARICH_RI_/).to_h { |key| [key, nil] }.merge(
      "RI" => nil, "RI_PAGER" => "cat", "PAGER" => "cat", "NO_COLOR" => nil,
      "TERM" => "xterm-256color", "BAT_THEME" => "ansi"
    )
    @directory = Dir.mktmpdir("rich-ri-comparison-")
    @svg = []
  end

  def run
    ruby = command("bundle", "exec", "ruby", "-rrdoc", "-e",
                   'print ["Ruby", RUBY_VERSION, "/ RDoc", RDoc::VERSION].join(" ")')
    commands = {
      "ri -f ansi" => ["bundle", "exec", "ri", "--no-pager", "-f", "ansi", "--width=#{COLUMNS}", QUERY],
      "rich-ri" => ["bundle", "exec", "ruby", "-Ilib", "exe/rich-ri", "--no-config", "--no-pager",
                    "--color=always", "--width=#{COLUMNS}", QUERY]
    }
    captures = commands.to_h { |name, args| [name, terminal_rows(capture(name, args))] }
    render(captures, ruby)
    puts "Raw captures and SVG: #{@directory}"
    puts "#{OUTPUT}: #{File.size(OUTPUT)} bytes"
  end

  def command(*)
    output, error, status = Open3.capture3(@environment, *, chdir: ROOT)
    raise "Command failed: #{error.strip}" unless status.success?

    output
  end

  def capture(name, args)
    raw = command(*args)
    raise "Missing colors in #{name}" unless raw.match?(SGR)

    File.write(File.join(@directory, "#{name}.ansi"), raw)
    raw
  end

  def default_style
    { fg: FOREGROUND, bg: PANEL, bold: false, italic: false, underline: false, reverse: false }
  end

  def apply_sgr(style, code)
    return default_style if code.zero?

    case code
    when *ATTRIBUTES.keys then style[ATTRIBUTES.fetch(code)] = code < 20
    when 39 then style[:fg] = FOREGROUND
    when 49 then style[:bg] = PANEL
    when 30..37 then style[:fg] = PALETTE.fetch(code - 30)
    when 90..97 then style[:fg] = PALETTE.fetch(code - 90 + 8)
    else raise "Unsupported SGR #{code}; update the renderer before using this capture"
    end
    style
  end

  def terminal_rows(raw)
    style = default_style
    raw.lines.flat_map do |line|
      cells = []
      line.chomp.scan(/\e\[[\d;]*m|./).each do |token|
        if (match = SGR.match(token))
          codes = match[1].empty? ? [0] : match[1].split(";", -1).map(&:to_i)
          codes.each { |code| style = apply_sgr(style, code) }
        else
          # This page is ASCII; fail if future documentation needs wide cells.
          raise "Unexpected character: #{token.inspect}" unless token.match?(/\A[ -~]\z/)

          cells << [token, style.dup]
        end
      end
      cells.empty? ? [[]] : cells.each_slice(COLUMNS).to_a
    end
  end

  def element(name, attributes, content = "")
    attributes = attributes.map { |key, value| "#{key}=\"#{CGI.escapeHTML(value.to_s)}\"" }.join(" ")
    "<#{name} #{attributes}>#{content}</#{name}>"
  end

  def text(left, top, value, size: 22, **attributes)
    @svg << element("text", { x: left, y: top, fill: FOREGROUND, "font-family" => "monospace", "font-size" => size,
                              "xml:space" => "preserve" }.merge(attributes), CGI.escapeHTML(value))
  end

  def rectangle(left, top, width, height, **attributes)
    @svg << element("rect", { x: left, y: top, width:, height: }.merge(attributes))
  end

  def draw_cell(left, top, char, style)
    fg, bg = style.values_at(:fg, :bg)
    fg, bg = bg, fg if style[:reverse]
    rectangle(left, top, CELL, LINE_HEIGHT, fill: bg) unless bg == PANEL
    text(left, top + 24, char, fill: fg, "font-weight" => style[:bold] ? "bold" : "normal",
                               "font-style" => style[:italic] ? "italic" : "normal")
    rectangle(left, top + 27, CELL, 1, fill: fg) if style[:underline]
  end

  def panel(name, rows, index, height)
    left = 30 + (index * (PANEL_WIDTH + 24))
    rectangle(left, 24, PANEL_WIDTH, height - 88, fill: PANEL, rx: 15, stroke: "#313244")
    text(left + 26, 68, name, size: 28, "font-family" => "sans-serif", "font-weight" => "bold")
    detail = index.zero? ? "Built-in ANSI formatter" : "Ruby syntax highlighting"
    text(left + PANEL_WIDTH - 26, 64, detail, size: 21, fill: MUTED,
                                              "font-family" => "sans-serif", "text-anchor" => "end")
    rectangle(left, 88, PANEL_WIDTH, 1, fill: "#313244")
    text(left + 26, 136, "$ #{name} #{QUERY}")
    rows.each_with_index do |row, row_index|
      row.each_with_index do |(char, style), column|
        draw_cell(left + 26 + (column * CELL), 164 + (row_index * LINE_HEIGHT), char, style)
      end
    end
  end

  def render(captures, versions)
    width = (2 * PANEL_WIDTH) + 84
    height = 254 + (captures.values.map(&:length).max * LINE_HEIGHT)
    rectangle(0, 0, width, height, fill: BACKGROUND)
    captures.each_with_index { |(name, rows), index| panel(name, rows, index, height) }
    caption = "Complete #{QUERY} page · #{COLUMNS} columns · Same terminal palette · #{versions}"
    text(30, height - 20, caption, size: 21, fill: MUTED, "font-family" => "sans-serif")
    source = File.join(@directory, "comparison.svg")
    File.write(source, element("svg", { xmlns: "http://www.w3.org/2000/svg", width:, height: }, @svg.join("\n")))
    command("magick", source, "-strip", "-define", "png:color-type=2", OUTPUT)
  end
end

ReadmeComparison.new.run if $PROGRAM_NAME == __FILE__
