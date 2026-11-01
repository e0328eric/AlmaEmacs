; Function-like constructs introduce parameter scopes.
[
  (function_declaration)
  (lambda_expression)
  (block)
  (for_statement)
  (pattern_arm)
  (pattern_case_clause)
  (pattern_quote_expression)
  (code_expression)
] @local.scope

; Parameters
; Module parameters are definitions in the source-file scope, including defaults.
(module_parameter
  name: (identifier) @local.definition)
(receiver_parameter
  (self_expression) @local.definition)
(parameter
  name: (binding_list [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.definition))
(parameter
  name: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.definition)
(comptime_parameter
  name: (binding_list [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.definition))
(lambda_parameter
  name: (identifier) @local.definition)

; Local bindings prevent a same-named outer parameter from leaking through a
; shadowing declaration.
(variable_declaration
  name: (binding_list [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.definition))
(for_statement
  name: (identifier) @local.definition)
(for_statement
  index: (identifier) @local.definition)
(pattern_binding
  name: (identifier) @local.definition)
(pointer_pattern
  name: (identifier) @local.definition)

; Resolve value uses, keeping member names out of the local value namespace.
[
  (_expression/identifier)
  (_expression/code_splice_identifier)
  (_expression/non_hygienic_identifier)
  (_pattern/code_splice_identifier)
  (_pattern/non_hygienic_identifier)
  (self_expression)
] @local.reference

; Postfix bases bypass the expression supertype.
(postfix_expression
  object: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.reference)
(postfix_expression
  function: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.reference)
(postfix_expression
  argument: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.reference)
(postfix_expression
  procedure: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.reference)
(postfix_expression
  scope: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.reference)
(postfix_expression
  type: [
    (identifier)
    (code_splice_identifier)
    (non_hygienic_identifier)
  ] @local.reference)
(qualified_operator scope: (identifier) @local.reference)
(using_statement name: (identifier) @local.reference)
(asm_output_operand target: (identifier) @local.reference)
(structured_asm_output_operand target: (identifier) @local.reference)
