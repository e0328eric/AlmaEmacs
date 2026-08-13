[
  "if"
  "else"
  "while"
  "for"
  "return"
  "break"
  "continue"
  "struct"
  "union"
  "enum"
  "enum_flags"
  "using"
  "noalias"
  "defer"
  "where"
  "cast"
  "acast"
  "typeclass"
  "instance"
] @keyword

[
  "#comptime"
  "#lazy"
  "#import"
  "#load"
  "#private_section"
  "#thread_local"
  "#library"
  "#fn_ptr"
  "#c_ptr"
  "#as"
  "#empty"
  "#raw"
  "#aos"
  "#soa"
  "#operator"
  "#precedence"
  "#modify"
  "#expand"
  "#magic"
  "#foreign"
  "#memory"
  "#c_call"
  "#packed"
  "#no_context"
  "#dump"
  "#fallback"
  "#must"
  "#noreturn"
  "#returns_twice"
  "#inline"
  "#bytes"
  "#asm"
  "#push_context"
  "#push_allocator"
  "#if"
  "#insert"
  "#compile_error"
  "#pattern"
  "#try"
  "#minimal"
  "#falling"
  "#meaningful"
  "#code"
  "#string"
  "#simd"
  "#enable"
  "#disable"
  "#derive"
] @attribute

(comment) @comment
(string_literal) @string
(multiline_string_line) @string
(char_literal) @character
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(null_literal) @constant.builtin
(label_none_literal) @constant.builtin
(context_expression) @constant.builtin
(context_type) @type.builtin

; Give every identifier a baseline capture first. Context-specific captures below
; must come later so clients that resolve overlapping captures by query order do
; not paint functions, parameters, properties, and types as plain variables.
(identifier) @variable
(code_splice_identifier) @variable
(non_hygienic_identifier) @variable
(label) @label
(quoted_operator) @operator
(operator) @operator
(prefix_operator) @operator
(try_operator) @operator

; Types
(named_type [
  (identifier)
  (code_splice_identifier)
] @type)
(generic_type
  name: [
    (identifier)
    (code_splice_identifier)
  ] @type)
(generic_type
  member: [
    (identifier)
    (code_splice_identifier)
  ] @type)
(generic_type_variable
  name: (identifier) @type)
(type_constructor_pattern [
  (identifier)
  (code_splice_identifier)
] @type)
(generic_type_constructor_pattern
  name: [
    (identifier)
    (code_splice_identifier)
  ] @type)
(instance_declaration
  class: (identifier) @type)

(named_declaration
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
  ] @type.definition)
  [
    (function_pointer_type_declaration)
    (typeclass_declaration)
    (struct_declaration)
    (enum_flags_declaration)
    (enum_declaration)
    (union_declaration)
  ])
(nested_declaration
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
  ] @type.definition)
  [
    (struct_declaration)
    (enum_declaration)
    (union_declaration)
  ])
(typeclass_associated_type
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
  ] @type.definition))
(instance_associated_type
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
  ] @type.definition))

; Parameters
(named_argument name: (identifier) @variable.parameter)
(typeclass_parameter name: (identifier) @variable.parameter)
(lambda_parameter name: (identifier) @variable.parameter)
(parameter
  name: (binding_list [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @variable.parameter))
(parameter
  name: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @variable.parameter)
(comptime_parameter
  name: (binding_list [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @variable.parameter))
(fn_ptr_parameter name: (identifier) @variable.parameter)
(function_type
  (type_element name: (identifier) @variable.parameter))
(structured_asm_input_operand name: (identifier) @variable.parameter)
(structured_asm_output_operand name: (identifier) @variable.parameter)

; Properties
(struct_field name: (identifier) @property)
(union_field name: (identifier) @property)
(enum_variant name: (identifier) @constant)
(struct_literal_field name: (identifier) @property)
(struct_pattern_field name: (identifier) @property)
(shorthand_member_expression field: (identifier) @property)
(shorthand_member_pattern field: (identifier) @property)
(postfix_expression field: (identifier) @property)
(pattern_postfix_expression field: (identifier) @property)

; Functions
(named_declaration
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
    (quoted_operator)
  ] @function)
  (function_declaration))
(nested_declaration
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
    (quoted_operator)
  ] @function)
  (function_declaration))
(typeclass_method_signature
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
    (quoted_operator)
  ] @function))
(instance_method
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
    (quoted_operator)
  ] @function))
(postfix_expression
  function: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @function.call)
(postfix_expression
  function: (postfix_expression
    field: [
      (identifier)
      (code_splice_identifier)
    ] @function.method.call))
(memory_argument_reference
  function: (identifier) @function.call)

(library_modifier) @attribute
(inline_modifier) @attribute
(string_modifier) @attribute
(partial_directive) @attribute
(pattern_rest) @operator
(matrix_type "Matrix" @type.builtin)
(simd_type "Simd" @type.builtin)
(variadic_constraint (identifier) @type)
(minimal_method (identifier) @function)
(memory_simple_effect) @attribute
(memory_parameter_effect_kind) @attribute
(memory_release_effect "released_by" @attribute)
(memory_resource_effect ["resource" "released_by"] @attribute)
(asm_operand_direction) @keyword
(structured_asm_constraint_kind) @constant.builtin
(structured_asm_operand_flag) @attribute
(structured_asm_clobber_kind) @constant.builtin
(import_selector mode: _ @attribute)
(expand_directive mode: (identifier) @attribute)
