# frozen_string_literal: true

# This adapter never interrupts.
module JobIteration
  module InterruptionAdapters
    module NullAdapter
      class << self
        def call
          false
        end
      end
    end
  end
end
