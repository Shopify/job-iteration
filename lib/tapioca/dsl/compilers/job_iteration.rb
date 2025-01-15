# typed: strict
# frozen_string_literal: true

return unless defined?(JobIteration::Iteration)

module Tapioca
  module Dsl
    module Compilers
      class JobIteration < Compiler
        extend T::Sig

        ConstantType = type_member { { fixed: T.class_of(::JobIteration::Iteration) } }

        sig { override.void }
        def decorate
          return unless constant.instance_methods(false).include?(:build_enumerator)

          root.create_path(constant) do |job|
            method = constant.instance_method(:build_enumerator)
            constant_name = name_of(constant)
            expanded_parameters = compile_method_parameters_to_rbi(method).reject do |typed_param|
              typed_param.param.name == "cursor"
            end

            job.create_method(
              "perform_later",
              parameters: perform_later_parameters(expanded_parameters, constant_name),
              return_type: "T.any(#{constant_name}, FalseClass)",
              class_method: true,
            )

            job.create_method(
              "perform_now",
              parameters: expanded_parameters,
              return_type: "void",
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
            constant_name: T.nilable(String),
          ).returns(T::Array[RBI::TypedParam])
        end
        def perform_later_parameters(parameters, constant_name)
          if ::Gem::Requirement.new(">= 7.0").satisfied_by?(::ActiveJob.gem_version)
            parameters.reject! { |typed_param| RBI::BlockParam === typed_param.param }
            parameters + [create_block_param(
              "block",
              type: "T.nilable(T.proc.params(job: #{constant_name}).void)",
            )]
          else
            parameters
          end
        end

        def compile_method_parameters_to_rbi(method_def)
          signature = signature_of(method_def)
          method_def = signature.nil? ? method_def : signature.method
          method_types = parameters_types_from_signature(method_def, signature)

          parameters = T.let(method_def.parameters, T::Array[[Symbol, T.nilable(Symbol)]])

          parameters.each_with_index.flat_map do |(type, name), index|
            fallback_arg_name = "_arg#{index}"

            name = name ? name.to_s : fallback_arg_name
            name = fallback_arg_name unless valid_parameter_name?(name)
            method_type = T.must(method_types[index])

            case type
            when :req
              if signature && (type_value = signature.arg_types[index][1]) && type_value.is_a?(T::Types::FixedHash)
                type_value.types.map do |key, value|
                  create_kw_param(key.to_s, type: value.to_s)
                end
              else
                create_param(name, type: method_type)
              end
            when :opt
              create_opt_param(name, type: method_type, default: "T.unsafe(nil)")
            when :rest
              create_rest_param(name, type: method_type)
            when :keyreq
              create_kw_param(name, type: method_type)
            when :key
              create_kw_opt_param(name, type: method_type, default: "T.unsafe(nil)")
            when :keyrest
              create_kw_rest_param(name, type: method_type)
            when :block
              create_block_param(name, type: method_type)
            else
              raise "Unknown type `#{type}`."
            end
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
