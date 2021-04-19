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

class TimeCursorJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    return [["item", Time.now]].to_enum if cursor.nil?

    raise "This should never run; cursor is unserializable!"
  end

  def each_iteration(*)
  end
end

class TerminateJob < ActiveJob::Base
  def perform
    Process.kill("TERM", Process.pid)
  end
end
