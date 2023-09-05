# frozen_string_literal: true

require "resque"

module JobIteration
  module Integrations
    module ResqueIterationExtension # @private
      def initialize(*) # @private
        $resque_worker = self
        super
      end
    end

    # @private
    module ::Resque
      class Worker
        # The patch is required in order to call shutdown? on a Resque::Worker instance
        prepend(ResqueIterationExtension)
      end
    end

    JobIteration.interruption_adapter = -> { $resque_worker.try!(:shutdown?) }
  end
end
