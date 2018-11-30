# frozen_string_literal: true

require "test_helper"

class JobIterationTest < IterationUnitTest
  def test_that_it_has_a_version_number
    refute_nil(::JobIteration::VERSION)
  end
end
