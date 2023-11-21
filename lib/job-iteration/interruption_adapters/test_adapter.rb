# frozen_string_literal: true

module JobIteration
  module InterruptionAdapters
    TestAdapter = -> { false }

    register(:test, TestAdapter)
  end
end
