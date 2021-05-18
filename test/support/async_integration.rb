# frozen_string_literal: true

module JobIteration
  module Integrations
    # https://api.rubyonrails.org/classes/ActiveJob/QueueAdapters/AsyncAdapter.html
    module AsyncIntegration
      class << self
        def interruption_adapter
          false
        end
      end
    end
  end
end
