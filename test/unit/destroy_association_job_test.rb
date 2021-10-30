# frozen_string_literal: true

require "test_helper"

module JobIteration
  class DestroyAssociationJobTest < IterationUnitTest
    setup do
      skip unless defined?(ActiveRecord.queues) || defined?(ActiveRecord::Base.queues)

      @product = Product.first
      ["pink", "red"].each do |color|
        @product.variants.create!(color: color)
      end
    end

    test "destroys the associated records" do
      @product.destroy!

      assert_difference(->() { Variant.count }, -2) do
        work_job
      end
    end

    test "checks if owner was destroyed using custom method" do
      @product = SoftDeletedProduct.first
      @product.destroy!

      assert_difference(->() { Variant.count }, -2) do
        work_job
      end
    end

    test "throw an error if the record is not actually destroyed" do
      @product.destroy!
      Product.create!(id: @product.id, name: @product.name)

      assert_raises(ActiveRecord::DestroyAssociationAsyncError) do
        work_job
      end
    end

    private

    def work_job
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
      assert_equal(job["job_class"], "JobIteration::DestroyAssociationJob")
      ActiveJob::Base.execute(job)
    end
  end
end
