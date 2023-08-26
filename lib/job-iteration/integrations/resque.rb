# frozen_string_literal: true

require "resque"

module JobIteration
  module Integrations
    module Resque
      module IterationExtension
        def initialize(*)
          $resque_worker = self
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
          $resque_worker.try!(:shutdown?)
        end
      end
    end
  end
end
