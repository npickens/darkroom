# frozen_string_literal: true

class Uglifier
  def self.compile(content, *other)
    "[javascript:minify #{content.inspect}]"
  end
end
