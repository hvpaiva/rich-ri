# frozen_string_literal: true

# Evaluates the GitHub Actions expressions the workflows use, so a test checks what a rule
# decides rather than how it is written. It knows literals, contexts, !, ==, !=, && and ||.
class WorkflowExpression
  TOKEN = /'[^']*'|==|!=|&&|\|\||[!()]|[A-Za-z_][\w.-]*/

  class Unsupported < StandardError; end

  def self.render(template, context)
    template.gsub(/\$\{\{(.+?)\}\}/m) { new(Regexp.last_match(1), context).value.to_s }
  end

  def initialize(source, context)
    @tokens = source.scan(TOKEN)
    @context = context
  end

  def value
    result = either
    raise Unsupported, "cannot read #{@tokens.join(' ')}" unless @tokens.empty?

    result
  end

  private

  # && and || return one of their operands, as in JavaScript.
  def either
    result = both
    while accept("||")
      right = both
      result = right unless truthy?(result)
    end
    result
  end

  def both
    result = comparison
    while accept("&&")
      right = comparison
      result = right if truthy?(result)
    end
    result
  end

  def comparison
    result = unary
    while (operator = accept("==", "!="))
      right = unary
      result = (result == right) == (operator == "==")
    end
    result
  end

  def unary = accept("!") ? !truthy?(unary) : operand

  def operand
    token = @tokens.shift
    case token
    when "(" then either.tap { raise Unsupported, "missing )" unless accept(")") }
    when /\A'(.*)'\z/ then Regexp.last_match(1)
    when "true", "false" then token == "true"
    when "null" then nil
    else @context.dig(*token.split("."))
    end
  end

  def accept(*operators) = (@tokens.shift if operators.include?(@tokens.first))

  def truthy?(value) = ![false, nil, "", 0].include?(value)
end
