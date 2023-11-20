# frozen_string_literal: true

# frozen_stirng_literal: true

require "resque"

module JobIteration
  module InterruptionAdapters
    module ResqueAdapter
      # @private
      module IterationExtension
        def initialize(*)
          $resque_worker = self # rubocop:disable Style/GlobalVars
          super
        end
      end

      # @private
      module ::Resque
        class Worker
          # The patch is required in order to call shutdown? on a Resque::Worker instance
          prepend(IterationExtension)
        end
      end

      class << self
        def call
          $resque_worker.try!(:shutdown?) # rubocop:disable Style/GlobalVars
        end
      end
    end
  end
end
