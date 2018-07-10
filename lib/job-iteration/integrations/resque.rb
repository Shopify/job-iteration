# frozen_string_literal: true

require 'resque'

module JobIteration
  module Integrations
    # The trick is required in order to call shutdown? on a Resque::Worker instance
    module ResqueIterationExtension
      def initialize(*)
        $resque_worker = self
        super
      end
    end
    Resque::Worker.prepend(ResqueIterationExtension)

    module ResqueInterruptionAdapter
      extend self

      def shutdown?
        $resque_worker.try!(:shutdown?)
      end
    end

    JobIteration.interruption_adapter = ResqueInterruptionAdapter
  end
end
