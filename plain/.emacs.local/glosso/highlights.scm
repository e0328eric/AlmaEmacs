[
  "if"
  "ifx"
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
  "const"
  "volatile"
  "defer"
  "where"
  "cast"
  "acast"
  "typeclass"
  "instance"
  "distinct"
] @keyword

(caller_return_statement "`return" @keyword)
(caller_defer_statement "`defer" @keyword)

[
  "#comptime"
  "#lazy"
  "#import"
  "#export"
  "#module_params"
  "#thread_local"
  "#library"
  "#fn_ptr"
  "#as"
  "#empty"
  "#raw"
  "#aos"
  "#soa"
  "#operator"
  "#specialize"
  "#expand"
  "#magic"
  "#foreign"
  "#c_call"
  "#packed"
  "#align"
  "#link_section"
  "#no_context"
  "#dump"
  "#must"
  "#returns_twice"
  "#inline"
  "#bytes"
  "#asm"
  "#push_context"
  "#push_allocator"
  "#temp_scope"
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
  "#matrix"
  "#enable"
  "#disable"
  "#derive"
  "#assert"
  "#public"
  "#private"
] @attribute

(from_directive) @attribute
(comptime_modifier) @attribute

(comment) @comment
(string_literal) @string
(c_string_literal) @string
(byte_string_literal) @string
(multiline_string_line) @string
(char_literal) @character
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(null_literal) @constant.builtin
(label_none_literal) @constant.builtin
(context_expression) @constant.builtin
(source_location_expression) @constant.builtin
(context_type) @type.builtin
(self_type) @type.builtin
(never_type) @type.builtin
(self_expression) @variable.builtin

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
(for_pointer_binder) @operator
(suffix_operator) @operator
(range_operator) @operator
(binding_operator) @operator
(constant_pattern_operator) @operator
(try_operator) @operator
(postfix_expression [".*" ".&"] @operator)
(expression_statement [".*" ".&"] @operator)
(enum_variant "-" @operator)

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

; Keep this list aligned with `parser_builtin_type_name` in ../glosso.
(
  [
    (named_type (identifier) @type.builtin)
    (generic_type name: (identifier) @type.builtin)
    (type_constructor_pattern (identifier) @type.builtin)
    (generic_type_constructor_pattern name: (identifier) @type.builtin)
  ]
  (#any-of? @type.builtin
    "ssize" "usize" "rune" "bool"
    "str" "cstr" "string16" "cstring16"
    "type" "void" "any" "label"
    "Code" "Pattern" "Namespace" "Library" "Typeclass" "Macro"
    "s8" "s16" "s32" "s64" "s128"
    "u8" "u16" "u32" "u64" "u128"
    "f16" "f32" "f64" "f80" "f128"
    "c32" "c64" "c128" "c160" "c256"))

(named_declaration
  name: (declaration_name [
    (identifier)
    (code_splice_identifier)
  ] @type.definition)
  [
    (function_pointer_type_declaration)
    (typeclass_declaration)
    (distinct_type_declaration)
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
    (function_pointer_type_declaration)
    (typeclass_declaration)
    (distinct_type_declaration)
    (struct_declaration)
    (enum_flags_declaration)
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
(module_parameter name: (identifier) @variable.parameter)
(module_named_argument name: (identifier) @variable.parameter)
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
(expression_statement field: (identifier) @property)
(pattern_postfix_expression field: (identifier) @property)
(scoped_name_suffix name: (identifier) @property)

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
(inherent_method
  name: (identifier) @function)
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
(expression_statement
  field: [
    (identifier)
    (code_splice_identifier)
  ] @function.method.call
  . (argument_list))

(library_modifier) @attribute
(inline_modifier) @attribute
(string_modifier) @attribute
(partial_directive) @attribute
(pattern_rest) @operator
(matrix_type "Matrix" @type.builtin)
(simd_type "Simd" @type.builtin)
(variadic_constraint (identifier) @type)
(minimal_method (identifier) @function)
(asm_operand_direction) @keyword
(structured_asm_constraint_kind) @constant.builtin
(structured_asm_operand_flag) @attribute
(structured_asm_clobber_kind) @constant.builtin
; Import lists name declarations of the imported module. Capitalized names
; are types, classes, or namespaces by convention.
((import_list (identifier) @type)
  (#match? @type "^[A-Z]"))
(import_member scope: (identifier) @type)
(import_member member: (identifier) @property)
((import_member member: (identifier) @type)
  (#match? @type "^[A-Z]"))
(expand_directive mode: (identifier) @attribute)
(insert_scope "scope" @attribute)
(visibility_modifier ["unit" "to"] @attribute)
(operator_try_modifier "try" @attribute)
(operator_try_modifier target: (identifier) @type)
