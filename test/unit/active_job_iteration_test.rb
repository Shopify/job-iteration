# frozen_string_literal: true
require 'test_helper'

class JobIteration::IterationTest < Minitest::Test
  include JobIteration::TestHelper

  class SimpleIterationJob < ActiveJob::Base
    include JobIteration::Iteration

    cattr_accessor :records_performed, instance_accessor: false
    self.records_performed = []
    cattr_accessor :on_start_called, instance_accessor: false
    self.on_start_called = 0
    cattr_accessor :on_complete_called, instance_accessor: false
    self.on_complete_called = 0
    cattr_accessor :shop_current_selected, instance_accessor: false
    self.shop_current_selected = []
    cattr_accessor :on_shutdown_called, instance_accessor: false
    self.on_shutdown_called = 0

    on_start do
      self.class.on_start_called += 1
    end

    on_complete do
      self.class.on_complete_called += 1
    end

    on_shutdown do
      self.class.on_shutdown_called += 1
    end
  end

  class IterationJobsWithParams < SimpleIterationJob
    def build_enumerator(params, cursor:)
      enumerator_builder.build_times_enumerator(params.fetch(:times, 2), cursor: cursor)
    end

    def each_iteration(_record, params)
      self.class.records_performed << params
    end
  end

  class ActiveRecordIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_active_record_enumerator_on_records(
        Post.where(country: 'CA'),
        cursor: cursor,
        on_lock: :ignore
      )
    end

    def each_iteration(record, _params)
      self.class.records_performed << record
      self.class.shop_current_selected << Post.current.present?
    end
  end

  class AbortingActiveRecordIterationJob < ActiveRecordIterationJob
    def each_iteration(*)
      throw(:abort) if self.class.records_performed.size == 2
      super
    end
  end

  class AbortingBatchActiveRecordIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_active_record_enumerator_on_batches(
        Post.all,
        cursor: cursor,
        batch_size: 2
      )
    end

    def each_iteration(shops, _params)
      self.class.records_performed << shops
      throw(:abort) if self.class.records_performed.size == 2
    end
  end

  class OrderedActiveRecordIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_active_record_enumerator_on_records(
        Post.order('country DESC'),
        cursor: cursor
      )
    end

    def each_iteration(*)
    end
  end

  class LimitActiveRecordIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_active_record_enumerator_on_records(
        Post.limit(5),
        cursor: cursor
      )
    end

    def each_iteration(*)
    end
  end

  class MissingBuildEnumeratorJob < SimpleIterationJob
    def each_iteration(*)
    end
  end

  class NilEnumeratorIterationJob < SimpleIterationJob
    def build_enumerator(*)
    end

    def each_iteration(*)
    end
  end

  class PrivateIterationJob < SimpleIterationJob
    private

    def build_enumerator(_params, cursor:)
      enumerator_builder.build_times_enumerator(3, cursor: cursor)
    end

    def each_iteration(*)
    end
  end

  class MissingEachIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_times_enumerator(3, cursor: cursor)
    end
  end

  class MultipleColumnsActiveRecordIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_active_record_enumerator_on_records(
        Post.all,
        cursor: cursor,
        columns: [:updated_at, :id],
        batch_size: 2
      )
    end

    def each_iteration(record, _params)
      self.class.records_performed << record
    end
  end

  class SingleIterationJob < SimpleIterationJob
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_once_enumerator(cursor: cursor)
    end

    def each_iteration(record, _params)
      self.class.records_performed << record
    end
  end

  class FailingIterationJob < SimpleIterationJob
    retry_on RuntimeError, attempts: 3, wait: 0

    def build_enumerator(_params, cursor:)
      enumerator_builder.build_active_record_enumerator_on_records(
        Post.where(country: 'CA'),
        cursor: cursor
      )
    end

    def each_iteration(shop, _params)
      @called ||= 0
      raise if @called > 2
      self.class.records_performed << shop
      @called += 1
    end
  end

  class JobWithBuildEnumeratorReturningArray < SimpleIterationJob
    def build_enumerator(*)
      []
    end

    def each_iteration(*)
      raise "should never be called"
    end
  end

  class JobWithBuildEnumeratorReturningActiveRecordRelation < SimpleIterationJob
    def build_enumerator(*)
      Post.all
    end

    def each_iteration(*)
      raise "should never be called"
    end
  end

  def setup
    SimpleIterationJob.descendants.each do |klass|
      klass.records_performed = []
      klass.on_start_called = 0
      klass.on_complete_called = 0
      klass.on_shutdown_called = 0
    end
    super
  end

  def test_each_iteration_method_missing
    push(MissingEachIterationJob)
    error = assert_raises(ArgumentError) do
      work_one_job
    end
    assert_match(/Iteration job \(\S+\) must implement `each_iteration`/, error.to_s)
  end

  def test_build_enumerator_method_missing
    push(MissingBuildEnumeratorJob)
    error = assert_raises(ArgumentError) do
      work_one_job
    end
    assert_match(/Iteration job \(\S+\) must implement #build_enumerator/, error.to_s)
  end

  def test_build_enumerator_returns_nil
    push(NilEnumeratorIterationJob)
    work_one_job
  end

  def test_works_with_private_methods
    push(PrivateIterationJob)
    work_one_job
    assert_jobs_in_queue 0, :default

    assert_equal 1, PrivateIterationJob.on_start_called
    assert_equal 1, PrivateIterationJob.on_complete_called
    assert_equal 1, PrivateIterationJob.on_shutdown_called
  end

  def test_failing_job
    push(FailingIterationJob)

    assert_raises(RuntimeError) do
      work_one_job
    end
    assert_jobs_in_queue 1, :default

    processed_shops = Post.where(country: 'CA').order("id ASC").pluck(:id)

    attempt, cursor = last_interrupted_job(FailingIterationJob, :default)
    expected_cursor = processed_shops[2]
    assert_equal 1, attempt
    assert_equal expected_cursor, cursor
    assert_equal 3, FailingIterationJob.records_performed.size
    assert_equal 1, FailingIterationJob.on_start_called

    assert_raises(RuntimeError) do
      work_one_job
    end
    assert_jobs_in_queue 1, :default

    attempt, cursor = last_interrupted_job(FailingIterationJob, :default)
    expected_cursor = processed_shops[5]
    assert_equal 2, attempt
    assert_equal expected_cursor, cursor

    assert_equal 6, FailingIterationJob.records_performed.size
    assert_equal 1, FailingIterationJob.on_start_called
    assert_equal 0, FailingIterationJob.on_complete_called

    # two more retries
    2.times { assert_raises(RuntimeError) { work_one_job } }
    assert_jobs_in_queue 0, :default
  end

  def test_iteration_lock_queue_job
    iterate_exact_times(1.times)
    shop = shops(:snowdevil)
    lock_queue = IterationLockQueueJob.new(shop_id: shop.id).lock_queue

    3.times { |i| push(IterationLockQueueJob, n: i, shop_id: shop.id) }

    assert_jobs_in_queue 1, :default
    assert_tasks_in_lock_queue [0, 1, 2], lock_queue

    work_one_job
    _, cursor = last_interrupted_job(IterationLockQueueJob, :default)

    assert_nil cursor
    assert_jobs_in_queue 1, :default
    assert_equal 1, IterationLockQueueJob.on_start_called
    assert_tasks_in_lock_queue [1, 2], lock_queue

    continue_iterating
    work_one_job

    assert_equal 1, IterationLockQueueJob.on_start_called
    assert_jobs_in_queue 0, :default
    assert_tasks_in_lock_queue [], lock_queue
  end

  def test_shops
    iterate_exact_times(2.times)

    push(ActiveRecordIterationJob)

    assert_equal 0, ActiveRecordIterationJob.on_complete_called
    work_one_job

    assert_equal 2, ActiveRecordIterationJob.records_performed.size
    attempt, cursor = last_interrupted_job(ActiveRecordIterationJob, :default)
    assert_equal 0, attempt
    assert cursor

    work_one_job
    assert_equal 4, ActiveRecordIterationJob.records_performed.size
    attempt, cursor = last_interrupted_job(ActiveRecordIterationJob, :default)
    assert_equal 0, attempt
    assert cursor

    assert_equal 0, ActiveRecordIterationJob.on_complete_called
    assert_equal 2, ActiveRecordIterationJob.on_shutdown_called
  end

  def test_each_iteration_sets_shop_current_when_records_are_shops
    iterate_exact_times(2.times)

    push(ActiveRecordIterationJob)

    assert ActiveRecordIterationJob.shop_current_selected.all?
  end

  def test_podded_batches_complete
    shop = shops(:snowdevil)
    push(PoddedBatchedIterationJob, shop_id: shop.id)
    ids_process_order = shop.customers.reorder("id ASC").pluck(:id)

    work_one_job
    assert_jobs_in_queue 0, :default

    assert_equal [3, 3, 1], PoddedBatchedIterationJob.records_performed.map(&:size)
    assert_equal ids_process_order, PoddedBatchedIterationJob.records_performed.flatten.map(&:id)
  end

  def test_podded_batches_all_shops_locked_doesnt_yield
    push(PoddedMultiShopBatchedIterationJob)

    shops = Post.where(id: Customer.pluck(:shop_id)).to_a

    lock_shops(*shops) do
      work_one_job
    end

    assert_jobs_in_queue 0, :default

    assert_equal [], PoddedBatchedIterationJob.records_performed
    assert_equal 1, ActiveRecordIterationJob.on_complete_called
    assert_equal 1, ActiveRecordIterationJob.on_shutdown_called
  end

  def test_podded_batches
    iterate_exact_times(1.times)

    shop = shops(:snowdevil)
    push(PoddedBatchedIterationJob, shop_id: shop.id)
    ids_process_order = shop.customers.reorder("id ASC").pluck(:id)

    work_one_job
    assert_equal 1, PoddedBatchedIterationJob.records_performed.size
    assert_equal 3, PoddedBatchedIterationJob.records_performed.flatten.size
    assert_equal 1, PoddedBatchedIterationJob.on_start_called

    attempt, cursor = last_interrupted_job(PoddedBatchedIterationJob, :default)
    assert_equal 0, attempt
    assert_equal ids_process_order[2], cursor

    work_one_job
    assert_equal 2, PoddedBatchedIterationJob.records_performed.size
    assert_equal 6, PoddedBatchedIterationJob.records_performed.flatten.size
    assert_equal 1, PoddedBatchedIterationJob.on_start_called

    attempt, cursor = last_interrupted_job(PoddedBatchedIterationJob, :default)
    assert_equal 0, attempt
    assert_equal ids_process_order[5], cursor
    continue_iterating

    work_one_job
    assert_jobs_in_queue 0, :default
    assert_equal 3, PoddedBatchedIterationJob.records_performed.size
    assert_equal 7, PoddedBatchedIterationJob.records_performed.flatten.size

    assert_equal 1, PoddedBatchedIterationJob.on_start_called
    assert_equal 1, PoddedBatchedIterationJob.on_complete_called
  end

  def test_plain_enumerable
    iterate_exact_times(3.times)

    push(EnumerableIterationJob)

    work_one_job
    assert_equal [1, 2, 3], EnumerableIterationJob.records_performed
    assert_equal 1, EnumerableIterationJob.on_start_called

    attempt, cursor = last_interrupted_job(EnumerableIterationJob, :default)
    assert_equal 0, attempt
    assert_equal 2, cursor

    work_one_job
    assert_equal 1.upto(6).to_a, EnumerableIterationJob.records_performed
    assert_equal 1, EnumerableIterationJob.on_start_called

    attempt, cursor = last_interrupted_job(EnumerableIterationJob, :default)
    assert_equal 0, attempt
    assert_equal 5, cursor

    work_one_job
    assert_jobs_in_queue 0, :default
    assert_equal 7, EnumerableIterationJob.records_performed.size

    assert_equal 1.upto(7).to_a, EnumerableIterationJob.records_performed
    assert_equal 1, EnumerableIterationJob.on_start_called
    assert_equal 1, EnumerableIterationJob.on_complete_called
  end

  def test_plain_enumerable_can_resume_a_job_using_index_rather_than_position
    iterate_exact_times(3.times)

    push(EnumerableIterationJob)

    work_one_job

    _, cursor = last_interrupted_job(EnumerableIterationJob, :default)
    assert_equal 2, cursor
    assert_equal (1..3).to_a, EnumerableIterationJob.records_performed

    work_one_job

    _, cursor = last_interrupted_job(EnumerableIterationJob, :default)
    assert_equal 5, cursor
    assert_equal (1..6).to_a, EnumerableIterationJob.records_performed

    work_one_job

    assert_equal 1, EnumerableIterationJob.on_complete_called
    assert_equal (1..7).to_a, EnumerableIterationJob.records_performed
  end

  def test_podded
    iterate_exact_times(3.times)

    shop = shops(:snowdevil)
    push(PoddedIterationJob, shop_id: shop.id)
    ids_process_order = shop.customers.reorder("id ASC").pluck(:id)

    work_one_job
    assert_equal 3, PoddedIterationJob.records_performed.size
    assert_equal 1, PoddedIterationJob.on_start_called
    assert_equal 1, PoddedIterationJob.on_shutdown_called

    attempt, cursor = last_interrupted_job(PoddedIterationJob, :default)
    assert_equal 0, attempt
    assert_equal ids_process_order[2], cursor

    work_one_job
    assert_equal 6, PoddedIterationJob.records_performed.size
    assert_equal 1, PoddedIterationJob.on_start_called
    assert_equal 2, PoddedIterationJob.on_shutdown_called

    attempt, cursor = last_interrupted_job(PoddedIterationJob, :default)
    assert_equal 0, attempt
    assert_equal ids_process_order[5], cursor

    work_one_job
    assert_jobs_in_queue 0, PoddedIterationJob.queue_name
    assert_equal 7, PoddedIterationJob.records_performed.size

    assert_equal PoddedIterationJob.records_performed, PoddedIterationJob.records_performed.uniq
    assert_equal 1, PoddedIterationJob.on_start_called
    assert_equal 3, PoddedIterationJob.on_shutdown_called
    assert_equal 1, PoddedIterationJob.on_complete_called
  end

  def test_master_table_job
    push(MasterTableIterationJob)

    work_one_job

    assert_jobs_in_queue 0, MasterTableIterationJob.queue_name
    assert_equal Proxy.count, MasterTableIterationJob.records_performed.size
  end

  def test_multiple_columns
    iterate_exact_times(3.times)

    push(MultipleColumnsIterationJob)

    1.upto(3) do |iter|
      work_one_job
      _, cursor = last_interrupted_job(MultipleColumnsIterationJob, :default)

      last_processed_record = MultipleColumnsIterationJob.records_performed.last
      assert_equal [last_processed_record.title, last_processed_record.vendor,
                    last_processed_record.id, last_processed_record.updated_at.to_s(:db)], cursor

      assert_equal iter * 3, MultipleColumnsIterationJob.records_performed.size
    end

    assert_equal Product.all.order('title, vendor, id').limit(9), MultipleColumnsIterationJob.records_performed
  end

  def test_single_iteration
    push(SingleIterationJob)

    assert_equal 0, SingleIterationJob.on_start_called
    assert_equal 0, SingleIterationJob.on_complete_called

    work_one_job
    assert_jobs_in_queue 0, :default
    assert_equal 1, SingleIterationJob.on_start_called
    assert_equal 1, SingleIterationJob.on_complete_called
  end

  def test_reports_each_iteration_runtime
    push(SingleIterationJob)

    expected_tags = ["job_class:#{SingleIterationJob.name.underscore}"]

    BackgroundQueue.stubs(:max_iteration_runtime).returns(0)

    assert_statsd_measure('background_queue.iteration.each_iteration', tags: expected_tags) do
      assert_logs(:warn, /each_iteration runtime exceeded limit/, BackgroundQueue) do
        work_one_job
      end
    end
    assert_jobs_in_queue 0, :default
  end

  def test_relation_with_limit
    push(LimitActiveRecordIterationJob)

    error = assert_raises(ArgumentError) do
      work_one_job
    end
    assert_match(/The relation cannot use ORDER BY or LIMIT/, error.to_s)
  end

  def test_relation_with_order
    push(OrderedActiveRecordIterationJob)

    error = assert_raises(ArgumentError) do
      work_one_job
    end
    assert_match(/The relation cannot use ORDER BY or LIMIT/, error.to_s)
  end

  def test_cannot_override_perform
    error = assert_raises(RuntimeError) do
      Class.new(SimpleIterationJob) do
        def perform(*)
        end
      end
    end
    assert_match(/cannot redefine #perform/, error.to_s)
  end

  def test_passes_params_to_each_iteration
    params = { 'walrus' => 'best' }
    push(IterationJobsWithParams, params)
    work_one_job
    assert_equal [params, params], IterationJobsWithParams.records_performed
  end

  def test_passes_params_to_each_iteration_without_extra_information_on_interruption
    iterate_exact_times(1.times, job: IterationJobsWithParams)
    params = { 'walrus' => 'yes', 'morewalrus' => 'si' }
    push(IterationJobsWithParams, params)

    work_one_job
    assert_equal [params], IterationJobsWithParams.records_performed

    work_one_job
    assert_equal [params, params], IterationJobsWithParams.records_performed
  end

  def test_emits_metric_when_interrupted
    iterate_exact_times(2.times, job: ActiveRecordIterationJob)

    push(ActiveRecordIterationJob)

    assert_statsd_increment('background_queue.iteration.interrupted') do
      work_one_job
    end
  end

  def test_emits_metric_when_resumed
    iterate_exact_times(2.times)

    push(ActiveRecordIterationJob)

    assert_no_statsd_calls('background_queue.iteration.resumed') do
      work_one_job
    end

    assert_statsd_increment('background_queue.iteration.resumed') do
      work_one_job
    end
  end

  def test_log_completion_data
    iterate_exact_times(2.times)

    push(IterationJobsWithParams)

    assert_no_logs(:info, /\[JobIteration::Iteration\] Completed./, BackgroundQueue) do
      work_one_job
    end

    expected_log = /\[JobIteration::Iteration\] Completed. times_interrupted=1 total_time=\d\.\d{3}/
    assert_logs(:info, expected_log, BackgroundQueue) do
      work_one_job
    end
  end

  def test_aborting_in_each_iteration_job
    push(AbortingActiveRecordIterationJob)
    work_one_job
    assert_equal 2, AbortingActiveRecordIterationJob.records_performed.size
    assert_equal 1, AbortingActiveRecordIterationJob.on_complete_called
  end

  def test_aborting_in_batched_job
    push(AbortingBatchIterationJob)
    work_one_job
    assert_equal 2, AbortingBatchIterationJob.records_performed.size
    assert_equal [2, 2], AbortingBatchIterationJob.records_performed.map(&:size)
    assert_equal 1, AbortingBatchIterationJob.on_complete_called
  end

  def test_check_for_exit_after_iteration
    # supervisor = Class.new
    # Podding::Resque::WorkerSupervisor.stubs(:instance).returns(supervisor)

    push(IterationJobsWithParams, times: 3)

    # calls = sequence("calls")
    IterationJobsWithParams.any_instance.expects(:job_should_exit?).times(3).returns(false)
    # supervisor.expects(shutdown?: true).in_sequence(calls)

    work_one_job
  end

  def test_iteration_job_with_build_enumerator_returning_array
    push(IterationJobWithBuildEnumeratorReturningArray)

    error = assert_raises(ArgumentError) do
      work_one_job
    end
    assert_match(/#build_enumerator is expected to return Enumerator object, but returned Array/, error.to_s)
  end

  def test_iteration_job_with_build_enumerator_returning_relation
    push(IterationJobWithBuildEnumeratorReturningActiveRecordRelation)

    error = assert_raises(ArgumentError) do
      work_one_job
    end
    assert_match(/#build_enumerator is expected to return Enumerator object, but returned Shop::ActiveRecord_Relation/, error.to_s)
  end

  private

  def last_interrupted_job(job_class, queue)
    jobs = jobs_in_queue(queue)
    assert_equal 1, jobs.size

    job = jobs.last
    assert_equal job_class.name, job["class"]

    args = job["args"]
    [args[0]["attempt"], args[0]["cursor_position"]]
  end

  def push(job, *args)
    job.perform_later(*args)
  end

  def work_one_job
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
    ActiveJob::Base.execute(job)
  end
end
