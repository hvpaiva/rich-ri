# frozen_string_literal: true

module RichRI
  class Highlighter
    SHELL_FORMATS = %i[sh bash zsh shell].freeze
    SESSION_FORMATS = %i[console shell-session shell_session sh-session].freeze

    def initialize(enabled, theme: Theme.new, bat_theme: ENV.fetch("BAT_THEME", "base16"), shell_theme: "ansi")
      @enabled = enabled
      @theme = theme
      @bat_theme = bat_theme
      @shell_theme = shell_theme
      @cache = {}
    end

    def highlight(text, format = nil)
      text = RichRI.sanitize(text)
      return text unless @enabled

      @cache[[text, format]] ||= if %i[ruby rb rich_ri_signature].include?(format)
                                   ruby(text, signature: format == :rich_ri_signature)
                                 elsif format.nil?
                                   shell_session(text) || (ruby?(text) ? ruby(text) : text)
                                 elsif SHELL_FORMATS.include?(format)
                                   shell_session(text) || other_language(text, format, theme: @shell_theme)
                                 elsif SESSION_FORMATS.include?(format)
                                   shell_session(text) || text
                                 elsif %i[c cpp javascript js json yaml yml diff sql rbs].include?(format)
                                   other_language(text, format)
                                 else
                                   text
                                 end
    end

    def shell_prompt(line)
      match = /\A(?<indent>[ \t]*)(?<prompt>\$[ \t]+)(?<command>[^\r\n]+)(?<ending>\r?\n)?\z/.match(line)
      return unless match

      # Shellwords only tokenizes text; examples are never evaluated. Accept a
      # command name/path, optionally preceded by environment assignments.
      words = Shellwords.shellsplit(match[:command])
      # A here-document can contain literal "$ command" lines. Leave this
      # ambiguous, multi-line shell input alone rather than invent prompts.
      return if words.any? { |word| word.start_with?("<<") }

      words.shift while words.first&.match?(/\A[A-Za-z_]\w*=/)
      executable = words.first
      return unless executable&.match?(%r{\A(?:[A-Za-z_][\w.+-]*|(?:/|\./|\.\./|~/)\S+)\z})

      match
    rescue ArgumentError
      # Unclosed quotes and other ambiguous examples stay unclassified.
      nil
    end

    def shell_session(text)
      lines = text.lines
      first = lines.find { |line| !line.strip.empty? }
      initial = first && shell_prompt(first)
      return unless initial

      # Require the first meaningful line to be a prompt. This avoids treating
      # "$ command" inside a Ruby string/heredoc or ordinary prose as a shell.
      indent = initial[:indent]
      prompts = lines.map { |line| shell_prompt(line) }
      prompt_start = /\A#{Regexp.escape(indent)}\$[ \t]+/
      return if lines.zip(prompts).any? { |line, prompt| line.match?(prompt_start) && !prompt }

      output = +""
      index = 0
      while index < lines.length
        prompt = prompts[index]
        unless prompt && prompt[:indent] == indent
          output << lines[index]
          index += 1
          next
        end

        command, index = shell_command(lines, index, prompt)
        output << command
      end
      output
    end

    def shell_command(lines, index, prompt)
      prefixes = [prompt[:indent] + @theme.paint(prompt[:prompt], :code)]
      commands = [prompt[:command] + prompt[:ending].to_s]
      index += 1
      # Secondary prompts belong to input only after an explicit continuation.
      while index < lines.length && commands.last.sub(/\r?\n\z/, "")[/\\+\z/].to_s.length.odd?
        continuation = /\A(#{Regexp.escape(prompt[:indent])})(>[ \t]+)?(.*?)(\r?\n)?\z/.match(lines[index])
        break unless continuation && !continuation[3].empty?

        prefixes << (continuation[1] + @theme.paint(continuation[2].to_s, :code))
        commands << (continuation[3] + continuation[4].to_s)
        index += 1
      end
      source = commands.join
      highlighted = (@cache[[source, :shell_command]] ||= other_language(source, :bash, theme: @shell_theme))
      colored_lines = highlighted.lines
      colored_lines = commands unless colored_lines.length == commands.length
      [prefixes.zip(colored_lines).map(&:join).join, index]
    end

    def ruby?(text)
      # A bare word or a prose-like command can also parse as a Ruby call.
      return false unless text.match?(/[=\[\]{}'":.@]|\b(?:def|class|module|do|end|nil|true|false|require)\b/)

      Prism.parse_success?(text)
    end

    def ruby(text, signature: false)
      root, tokens = Prism.parse_lex(text).value
      roles = ruby_roles(root)
      tokens = tokens.map(&:first).reject { |token| token.type == :EOF }
      # Heredoc tokens need source order. Byte offsets preserve Unicode and all
      # un-tokenized whitespace, including deliberately incomplete examples.
      tokens.sort_by! { |token| token.location.start_offset }
      output = +""
      offset = 0
      previous = nil
      tokens.each_with_index do |token, index|
        start = token.location.start_offset
        finish = token.location.end_offset
        next if start < offset

        output << text.byteslice(offset...start)
        location, role = roles.bsearch { |candidate, _role| candidate.end_offset > start }
        role = nil unless location && location.start_offset <= start && finish <= location.end_offset
        role ||= token_role(token, previous, tokens[index + 1], signature)
        output << (role ? @theme.paint(token.value, role) : token.value)
        offset = finish
        previous = token unless %i[NEWLINE IGNORED_NEWLINE COMMENT].include?(token.type)
      end
      output << text.byteslice(offset..)
    rescue ArgumentError, EncodingError
      text
    end

    def ruby_roles(root)
      roles = []
      pending = [root]
      until pending.empty?
        node = pending.pop
        case node
        when Prism::DefNode
          roles << [node.name_loc, :method]
        when Prism::CallNode
          # Infix operators and indexing are also calls in Ruby's AST. Only
          # named calls and explicit receivers such as obj.+ use method colors.
          if node.message_loc && (node.call_operator_loc || node.name.to_s.match?(/\A[[:alpha:]_]/))
            roles << [node.message_loc, :method]
          end
        when Prism::SymbolNode
          roles << [node.location, :symbol]
        end
        pending.concat(node.compact_child_nodes)
      end
      roles.sort_by { |location, _role| location.start_offset }
    end

    def token_role(token, previous, following, signature)
      type = token.type.to_s
      return :comment if type.start_with?("COMMENT", "EMBDOC")
      return :symbol if type.start_with?("SYMBOL", "LABEL") || previous&.type == :SYMBOL_BEGIN
      return :code if %w[KEYWORD_NIL KEYWORD_TRUE KEYWORD_FALSE KEYWORD_SELF].include?(type)
      return :keyword if type.start_with?("KEYWORD_")
      return :number if type.match?(/INTEGER|FLOAT|RATIONAL|IMAGINARY/)
      return :constant if type == "CONSTANT"
      return :string if type.match?(/STRING|HEREDOC|REGEXP|PERCENT_(?:LOWER|UPPER)_|CHARACTER_LITERAL|BACKTICK/)
      return :code if type.match?(/VARIABLE|REFERENCE|EMBEXPR|EMBVAR/)
      return :method if type == "METHOD_NAME"

      # Signatures and incomplete examples can lack a complete syntax tree.
      if (type == "IDENTIFIER") && (signature || %i[DOT AMPERSAND_DOT COLON_COLON
                                                    KEYWORD_DEF].include?(previous&.type) || following&.value == "(")
        return :method
      end

      :operator if ruby_operator?(token)
    end

    def ruby_operator?(token)
      %i[PERCENT PERCENT_EQUAL].include?(token.type) ||
        %w[= => -> + - * / ** == === != =~ !~ < > <= >= <=> && || ! ~ & | ^
           << >> += -= *= /= **= &= |= ^= <<= >>= &&= ||= .. ... ? :].include?(token.value)
    end

    def other_language(text, format, theme: @bat_theme)
      language = { sh: "bash", shell: "bash", js: "javascript", yml: "yaml" }.fetch(format, format.to_s)
      output, status = Open3.capture2(
        "bat", "--no-config", "--language=#{language}", "--style=plain",
        "--color=always", "--paging=never", "--wrap=never",
        "--theme=#{theme}",
        stdin_data: text, err: File::NULL
      )
      # Do not let a highlighter change the document's contents.
      output = output.delete_suffix("\n") if !text.end_with?("\n") && output.end_with?("\n")
      status.success? && RichRI.plain(output) == text ? output : text
    rescue Errno::ENOENT
      text
    end
  end
end
