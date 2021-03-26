# frozen_string_literal: true

module SassC
  class Engine
    def initialize(content, *other)
      @content = content
    end

    def render
      "[css:minify #{@content.inspect}]"
    end
  end
end
