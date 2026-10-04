# frozen_string_literal: true

module RichRI
  SGR = /\e\[[\d;]*m/
  RESET = "\e[0m"
  COLORS = {
    title: "1;36", heading: "1;34", subheading: "1;35",
    code: "36", reference: "36", link: "4;36", label: "1;33",
    muted: "90", emphasis: "3", bold: "1", strike: "9",
    keyword: "35", string: "32", number: "33", constant: "33",
    symbol: "33", method: "36", comment: "90", operator: "35"
  }.freeze

  def self.plain(text)
    text.gsub(SGR, "")
  end

  # Documentation may contain literal terminal controls. Show them as text;
  # only styles produced by this reader may reach the terminal as escapes.
  def self.sanitize(text)
    text.gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u0080-\u009f\u202a-\u202e\u2066-\u2069]|\r(?!\n)/) do |char|
      format("\\u%04x", char.ord)
    end
  end

  def self.width(text)
    Reline::Unicode.calculate_width(text, true)
  end

  # Each word has balanced SGRs: less resets colors at newlines, and wrapping
  # must never make a style bleed into the next paragraph or the shell prompt.
  def self.paint(text, *roles, enabled: true)
    Theme.new.paint(text, *roles, enabled:)
  end
end
