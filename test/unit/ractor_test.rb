# frozen_string_literal: true

require "test_helper"
require "sorbet-runtime"

class RactorTest < ActiveSupport::TestCase
  module CustomInterruptionAdapter
    class << self
      def call
        false
      end
    end
  end

  class JobWithSorbetSignatures < ActiveJob::Base
    extend T::Sig
    include JobIteration::Iteration

    # sorbet-runtime replaces the wrappers of methods that are never checked with the original methods once it has
    # built their signatures, which is what lets other Ractors call them.
    sig { params(cursor: T.untyped).returns(T::Enumerator[T.untyped]).checked(:never) }
    def build_enumerator(cursor:)
      enumerator_builder.build_times_enumerator(2, cursor: cursor)
    end

    sig { params(number: Integer, name: String).void.checked(:never) }
    def each_iteration(number, name:)
    end
  end

  test "max_job_runtime can be read in a non-main Ractor" do
    with_global_setting(:max_job_runtime, 1.minute) do
      assert_equal(60, in_ractor { JobIteration.max_job_runtime.to_i })
    end
  end

  test "default_retry_backoff can be read in a non-main Ractor" do
    with_global_setting(:default_retry_backoff, 10.seconds) do
      assert_equal(10, in_ractor { JobIteration.default_retry_backoff.to_i })
    end
  end

  test "interruption adapters can be looked up in a non-main Ractor" do
    adapters = in_ractor { [:test, :sidekiq].map { |name| JobIteration::InterruptionAdapters.lookup(name) } }

    assert_equal(
      [JobIteration::InterruptionAdapters::NullAdapter, JobIteration::InterruptionAdapters::SidekiqAdapter],
      adapters,
    )
  end

  test "interruption adapters can be looked up in a non-main Ractor after one is registered" do
    register = -> { JobIteration::InterruptionAdapters.register(:ractor_test, CustomInterruptionAdapter) }
    adapter = in_ractor(prepare: register) { JobIteration::InterruptionAdapters.lookup(:ractor_test) }

    assert_equal(CustomInterruptionAdapter, adapter)
  end

  test "the parameters of methods with Sorbet signatures can be read in a non-main Ractor" do
    parameters = in_ractor(prepare: -> { T::Utils.run_all_sig_blocks }) do
      job = JobWithSorbetSignatures.allocate
      [:build_enumerator, :each_iteration].map { |method_name| job.send(:method_parameters, method_name) }
    end

    assert_equal([[[:keyreq, :cursor]], [[:req, :number], [:keyreq, :name]]], parameters)
  end

  private

  def with_global_setting(name, value)
    original = JobIteration.public_send(name)
    JobIteration.public_send(:"#{name}=", value)
    yield
  ensure
    JobIteration.public_send(:"#{name}=", original)
  end

  # Calls the block with the arguments in a new Ractor and returns its value. The Ractor runs in a forked process, after
  # `prepare` is called there, so the other tests never share a process with a Ractor.
  def in_ractor(*arguments, prepare: nil, &block)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      Warning[:experimental] = false
      prepare&.call
      ractor = Ractor.new(*arguments, &block)
      result = [:value, ractor.respond_to?(:value) ? ractor.value : ractor.take]
    rescue Exception => error # rubocop:disable Lint/RescueException
      error = error.cause if error.is_a?(Ractor::RemoteError)
      result = [:error, "#{error.class}: #{error.message}"]
    ensure
      writer.write(Marshal.dump(result))
      writer.close
      exit!
    end
    writer.close
    status, value = Marshal.load(reader.read)
    Process.wait(pid)
    flunk("The Ractor raised #{value}") if status == :error
    value
  ensure
    reader&.close
  end
end
