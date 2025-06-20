# typed: strict
# frozen_string_literal: true

return unless defined?(JobIteration::Iteration)

module Tapioca
  module Dsl
    module Compilers
      class JobIteration < Compiler
        extend T::Sig
        extend T::Generic

        ConstantType = type_member { { fixed: T.class_of(::JobIteration::Iteration) } }
        PARAM_TYPES_IN_ORDER = [
          RBI::Param,
          RBI::OptParam,
          RBI::RestParam,
          RBI::KwParam,
          RBI::KwOptParam,
          RBI::KwRestParam,
          RBI::BlockParam,
        ].freeze

        sig { override.void }
        def decorate
          return unless constant.instance_methods(false).include?(:build_enumerator)

          root.create_path(constant) do |job|
            method = constant.instance_method(:build_enumerator)
            constant_name = name_of(constant)
            signature = signature_of(method)

            parameters = compile_method_parameters_to_rbi(method).reject do |typed_param|
              typed_param.param.name == "cursor"
            end

            if signature
              fixed_hash_args = signature.arg_types.select { |arg_type| T::Types::FixedHash === arg_type[1] }.to_h
              expanded_parameters = parameters.flat_map do |typed_param|
                if (hash_type = fixed_hash_args[typed_param.param.name.to_sym])
                  hash_type.types.map do |key, value|
                    if value.name.start_with?("T.nilable")
                      create_kw_opt_param(key.to_s, type: value.to_s, default: "nil")
                    else
                      create_kw_param(key.to_s, type: value.to_s)
                    end
                  end
                else
                  typed_param
                end
              end
            else
              expanded_parameters = parameters
            end

            # Sorbet expects optional keyword arguments to be after required keyword arguments.
            expanded_parameters.sort_by! { |typed_param| PARAM_TYPES_IN_ORDER.index(typed_param.param.class) }

            number_of_generic_type_members = Tapioca::Runtime::GenericTypeRegistry.lookup_type_variables(constant)&.size

            returned_job_class = if number_of_generic_type_members&.nonzero?
              "#{constant_name}[#{number_of_generic_type_members.times.map { "T.untyped" }.join(", ")}]"
            else
              constant_name
            end

            job.create_method(
              "perform_later",
              parameters: perform_later_parameters(expanded_parameters, returned_job_class),
              return_type: "T.any(#{returned_job_class}, FalseClass)",
              class_method: true,
            )

            job.create_method(
              "perform_now",
              parameters: expanded_parameters,
              return_type: "T.any(NilClass, Exception)",
              class_method: true,
            )

            job.create_method(
              "perform",
              parameters: expanded_parameters,
              return_type: "void",
              class_method: false,
            )
          end
        end

        private

        sig do
          params(
            parameters: T::Array[RBI::TypedParam],
            returned_job_class: String,
          ).returns(T::Array[RBI::TypedParam])
        end
        def perform_later_parameters(parameters, returned_job_class)
          if ::Gem::Requirement.new(">= 7.0").satisfied_by?(::ActiveJob.gem_version)
            parameters.reject! { |typed_param| RBI::BlockParam === typed_param.param }
            parameters + [create_block_param(
              "block",
              type: "T.nilable(T.proc.params(job: #{returned_job_class}).void)",
            )]
          else
            parameters
          end
        end

        class << self
          extend T::Sig

          sig { override.returns(T::Enumerable[Module]) }
          def gather_constants
            all_classes.select { |c| ::JobIteration::Iteration > c }
          end
        end
      end
    end
  end
end
