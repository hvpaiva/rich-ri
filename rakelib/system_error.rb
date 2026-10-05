# frozen_string_literal: true

module SystemError
  # Ruby appends where the call failed and the path; callers name the path in their own words.
  def self.reason(error) = SystemCallError.new(nil, error.errno).message
end
