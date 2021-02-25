# frozen_string_literal: true

class IterationJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    enumerator_builder.times(4, cursor: cursor)
  end

  def each_iteration(omg)
    if omg == 0 || omg == 2
      Process.kill("TERM", Process.pid)
    end
    sleep(1)
  end
end

class TerminateJob < ActiveJob::Base
  def perform
    Process.kill("TERM", Process.pid)
  end
end

class CallbacksJob < IterationJob
  include JobIteration::Iteration

  before_enqueue { puts "callback: before_enqueue" }
  on_shutdown { puts "callback: on_shutdown" }

  def build_enumerator(cursor:)
    enumerator_builder.times(2, cursor: cursor)
  end

  def each_iteration(element)
    Process.kill("TERM", Process.pid) if element == 0
    sleep(1)
  end
end
