# frozen_string_literal: true

module JobIteration
  module InterruptionAdapters
    InlineAdapter = -> { false }

    register(:inline, InlineAdapter)
  end
end
