# typed: strict
# frozen_string_literal: true

require "test_helper"
require "tapioca/internal"
# JobIteration compiler requires Tapioca 0.13.0+
return if Gem::Version.new(Tapioca::VERSION) < Gem::Version.new("0.13.0")
require "tapioca/helpers/test/dsl_compiler"
require "tapioca/dsl/compilers/job_iteration"

module Tapioca
  module Dsl
    module Compilers
      class JobIterationTest < Minitest::Test
        extend T::Sig
        extend Tapioca::Helpers::Test::Template
        include Tapioca::Helpers::Test::DslCompiler

        def setup
          require "job-iteration"
          require "tapioca/dsl/compilers/job_iteration"
          use_dsl_compiler(Tapioca::Dsl::Compilers::JobIteration)
        end

        def test_gathers_constants_only_for_jobs_that_include_job_iteration
          add_ruby_file("job.rb", <<~RUBY)
            class FooJob < ActiveJob::Base
            end

            class BarJob < ActiveJob::Base
              include JobIteration::Iteration
            end
          RUBY

          assert_includes(gathered_constants, "BarJob")
          refute_includes(gathered_constants, "FooJob")
        end

        def test_generates_an_empty_rbi_file_if_there_is_no_build_enumerator_method
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration
            end
          RUBY

          expected = <<~RBI
            # typed: strong
          RBI

          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              def build_enumerator(user_id, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(user_id: T.untyped).void }
              def perform(user_id); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(user_id: T.untyped, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id, &block); end
            <% else %>
                sig { params(user_id: T.untyped).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id); end
            <% end %>

                sig { params(user_id: T.untyped).void }
                def perform_now(user_id); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_with_keyword_parameter
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              def build_enumerator(user_id:, profile_id:, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(user_id: T.untyped, profile_id: T.untyped).void }
              def perform(user_id:, profile_id:); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(user_id: T.untyped, profile_id: T.untyped, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id:, profile_id:, &block); end
            <% else %>
                sig { params(user_id: T.untyped, profile_id: T.untyped).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id:, profile_id:); end
            <% end %>

                sig { params(user_id: T.untyped, profile_id: T.untyped).void }
                def perform_now(user_id:, profile_id:); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_signature
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              extend T::Sig
              sig { params(user_id: Integer, cursor: T.untyped).returns(T::Array[T.untyped]) }
              def build_enumerator(user_id, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(user_id: ::Integer).void }
              def perform(user_id); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(user_id: ::Integer, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id, &block); end
            <% else %>
                sig { params(user_id: ::Integer).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id); end
            <% end %>

                sig { params(user_id: ::Integer).void }
                def perform_now(user_id); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_signature_with_keyword_parameter
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              extend T::Sig
              sig { params(user_id: Integer, profile_id: Integer, cursor: T.untyped).returns(T::Array[T.untyped]) }
              def build_enumerator(user_id:, profile_id:, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(user_id: ::Integer, profile_id: ::Integer).void }
              def perform(user_id:, profile_id:); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(user_id: ::Integer, profile_id: ::Integer, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id:, profile_id:, &block); end
            <% else %>
                sig { params(user_id: ::Integer, profile_id: ::Integer).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id:, profile_id:); end
            <% end %>

                sig { params(user_id: ::Integer, profile_id: ::Integer).void }
                def perform_now(user_id:, profile_id:); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_with_multiple_parameters
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              extend T::Sig
              sig { params(user_id: Integer, name: String, cursor: T.untyped).returns(T::Array[T.untyped]) }
              def build_enumerator(user_id, name, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(user_id: ::Integer, name: ::String).void }
              def perform(user_id, name); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(user_id: ::Integer, name: ::String, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id, name, &block); end
            <% else %>
                sig { params(user_id: ::Integer, name: ::String).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id, name); end
            <% end %>

                sig { params(user_id: ::Integer, name: ::String).void }
                def perform_now(user_id, name); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_with_aliased_hash_parameter
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              Params = T.type_alias { { user_id: Integer, name: String } }

              extend T::Sig
              sig { params(params: Params, cursor: T.untyped).returns(T::Array[T.untyped]) }
              def build_enumerator(params, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(user_id: ::Integer, name: ::String).void }
              def perform(user_id:, name:); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(user_id: ::Integer, name: ::String, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id:, name:, &block); end
            <% else %>
                sig { params(user_id: ::Integer, name: ::String).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(user_id:, name:); end
            <% end %>

                sig { params(user_id: ::Integer, name: ::String).void }
                def perform_now(user_id:, name:); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_with_nested_hash_parameter
          add_ruby_file("job.rb", <<~RUBY)
            class ResourceType; end
            class Locale; end

            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              extend T::Sig
              sig do
                params(
                  params: { shop_id: Integer, resource_types: T::Array[ResourceType], locale: Locale, metadata: T.nilable(String) },
                  cursor: T.untyped
                ).returns(T::Array[T.untyped])
              end
              def build_enumerator(params, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(shop_id: ::Integer, resource_types: T::Array[::ResourceType], locale: ::Locale, metadata: T.nilable(::String)).void }
              def perform(shop_id:, resource_types:, locale:, metadata:); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(shop_id: ::Integer, resource_types: T::Array[::ResourceType], locale: ::Locale, metadata: T.nilable(::String), block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(shop_id:, resource_types:, locale:, metadata:, &block); end
            <% else %>
                sig { params(shop_id: ::Integer, resource_types: T::Array[::ResourceType], locale: ::Locale, metadata: T.nilable(::String)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(shop_id:, resource_types:, locale:, metadata:); end
            <% end %>

                sig { params(shop_id: ::Integer, resource_types: T::Array[::ResourceType], locale: ::Locale, metadata: T.nilable(::String)).void }
                def perform_now(shop_id:, resource_types:, locale:, metadata:); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end

        def test_generates_correct_rbi_file_for_job_with_build_enumerator_method_with_complex_hash_parameter
          add_ruby_file("job.rb", <<~RUBY)
            class NotifyJob < ActiveJob::Base
              include JobIteration::Iteration

              extend T::Sig
              sig do
                params(
                  params: {
                    shop_ids: T.any(Integer, T::Array[Integer]),
                    profile_ids: T.any(Integer, T::Array[Integer]),
                    extension_ids: T.any(Integer, T::Array[Integer]),
                    foo: Symbol,
                    bar: String
                  },
                  cursor: T.untyped
                ).returns(T::Array[T.untyped])
              end
              def build_enumerator(params, cursor:)
                # ...
              end
            end
          RUBY

          expected = template(<<~RBI)
            # typed: strong

            class NotifyJob
              sig { params(shop_ids: T.any(::Integer, T::Array[::Integer]), profile_ids: T.any(::Integer, T::Array[::Integer]), extension_ids: T.any(::Integer, T::Array[::Integer]), foo: ::Symbol, bar: ::String).void }
              def perform(shop_ids:, profile_ids:, extension_ids:, foo:, bar:); end

              class << self
            <% if rails_version(">= 7.0") %>
                sig { params(shop_ids: T.any(::Integer, T::Array[::Integer]), profile_ids: T.any(::Integer, T::Array[::Integer]), extension_ids: T.any(::Integer, T::Array[::Integer]), foo: ::Symbol, bar: ::String, block: T.nilable(T.proc.params(job: NotifyJob).void)).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(shop_ids:, profile_ids:, extension_ids:, foo:, bar:, &block); end
            <% else %>
                sig { params(shop_ids: T.any(::Integer, T::Array[::Integer]), profile_ids: T.any(::Integer, T::Array[::Integer]), extension_ids: T.any(::Integer, T::Array[::Integer]), foo: ::Symbol, bar: ::String).returns(T.any(NotifyJob, FalseClass)) }
                def perform_later(shop_ids:, profile_ids:, extension_ids:, foo:, bar:); end
            <% end %>

                sig { params(shop_ids: T.any(::Integer, T::Array[::Integer]), profile_ids: T.any(::Integer, T::Array[::Integer]), extension_ids: T.any(::Integer, T::Array[::Integer]), foo: ::Symbol, bar: ::String).void }
                def perform_now(shop_ids:, profile_ids:, extension_ids:, foo:, bar:); end
              end
            end
          RBI
          assert_equal(expected, rbi_for(:NotifyJob))
        end
      end
    end
  end
end
