# frozen_string_literal: true

module SassC
  class Engine
    def render(*)
      raise('SassC::Engine#compile must be stubbed in tests')
    end
  end
end
