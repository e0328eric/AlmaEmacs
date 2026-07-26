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
  "#run"
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
  "#c_call"
  "#no_context"
  "#dump"
  "#fallback"
  "#must"
  "#noreturn"
  "#inline"
  "#bytes"
  "#asm"
  "#push_context"
  "#push_allocator"
  "#if"
  "#insert"
  "#compile_error"
  "#pattern"
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

(named_argument name: (identifier) @variable.parameter)
(typeclass_parameter name: (identifier) @variable.parameter)
(lambda_parameter name: (identifier) @variable.parameter)
(declaration_name) @function
(function_declaration (parameter_list (parameter name: (binding_list (identifier) @variable.parameter))))
(parameter name: (binding_list (identifier) @variable.parameter))
(parameter name: (identifier) @variable.parameter)
(struct_field name: (identifier) @property)
(union_field name: (identifier) @property)
(enum_variant name: (identifier) @constant)
(struct_literal_field name: (identifier) @property)
(struct_pattern_field name: (identifier) @property)
(shorthand_member_expression field: (identifier) @property)
(shorthand_member_pattern field: (identifier) @property)
(postfix_expression field: (identifier) @property)
(pattern_postfix_expression field: (identifier) @property)
(postfix_expression function: (identifier) @function)
(library_modifier) @attribute
(inline_modifier) @attribute
(partial_directive) @attribute
(pattern_rest) @operator
(matrix_type "Matrix" @type.builtin)
(simd_type "Simd" @type.builtin)
(variadic_constraint (identifier) @type)
(minimal_method (identifier) @function)
(import_selector mode: _ @attribute)
(expand_directive mode: (identifier) @attribute)

(identifier) @variable
(code_splice_identifier) @variable
(non_hygienic_identifier) @variable
(label) @label
(quoted_operator) @operator
(operator) @operator
(prefix_operator) @operator
