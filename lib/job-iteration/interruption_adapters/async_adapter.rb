# frozen_string_literal: true

module JobIteration
  module InterruptionAdapters
    AsyncAdapter = -> { false }

    register(:async, AsyncAdapter)
  end
end
