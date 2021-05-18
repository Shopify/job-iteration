# frozen_string_literal: true

require "resque"

module JobIteration
  module Integrations
    class ResqueIntegration
      module ResqueIterationExtension # @private
        def initialize(*) # @private
          $resque_worker = self
          super
        end
      end

      # The patch is required in order to call shutdown? on a Resque::Worker instance
      Resque::Worker.prepend(ResqueIterationExtension)

      def stopping?
        $resque_worker.try!(:shutdown?)
      end
    end
  end
end
