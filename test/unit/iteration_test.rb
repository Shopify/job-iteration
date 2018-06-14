# frozen_string_literal: true

require "test_helper"

class JobIterationTest < Minitest::Test
  def test_that_it_has_a_version_number
    # puts Post.pluck(:id)
    refute_nil ::JobIteration::VERSION
  end

  def test_it_does_something_useful
    # puts Post.pluck(:id)
    # assert false
  end
end
