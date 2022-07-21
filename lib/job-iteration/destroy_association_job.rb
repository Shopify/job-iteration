# frozen_string_literal: true

require "active_job"

module JobIteration
  # Port of https://github.com/rails/rails/blob/main/activerecord/lib/active_record/destroy_association_async_job.rb
  # (MIT license) but instead of +ActiveRecord::Batches+ this job uses the +Iteration+ API to destroy associated
  # objects.
  #
  # @see https://guides.rubyonrails.org/association_basics.html Using the 'dependent: :destroy_async' option
  # @see https://guides.rubyonrails.org/configuring.html#configuring-active-record Configuring Active Record
  #   'destroy_association_async_job', 'destroy_association_async_batch_size' and 'queues.destroy' options
  class DestroyAssociationJob < ::ApplicationJob
    include(JobIteration::Iteration)

    queue_as do
      # Compatibility with Rails 7 and 6.1
      queues = defined?(ActiveRecord.queues) ? ActiveRecord.queues : ActiveRecord::Base.queues
      queues[:destroy]
    end

    discard_on(ActiveJob::DeserializationError)

    def build_enumerator(params, cursor:)
      association_model = params[:association_class].constantize
      owner_class = params[:owner_model_name].constantize
      owner = owner_class.find_by(owner_class.primary_key.to_sym => params[:owner_id])

      unless owner_destroyed?(owner, params[:ensuring_owner_was_method])
        raise ActiveRecord::DestroyAssociationAsyncError, "owner record not destroyed"
      end

      enumerator_builder.active_record_on_records(
        association_model.where(params[:association_primary_key_column] => params[:association_ids]),
        cursor: cursor,
      )
    end

    def each_iteration(record, _params)
      record.destroy
    end

    private

    def owner_destroyed?(owner, ensuring_owner_was_method)
      !owner || (ensuring_owner_was_method && owner.public_send(ensuring_owner_was_method))
    end
  end
end
