; Function-like constructs introduce parameter scopes.
[
  (function_declaration)
  (lambda_expression)
  (block)
  (for_statement)
  (pattern_arm)
] @local.scope

; Parameters
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

; References
[
  (identifier)
  (code_splice_identifier)
  (non_hygienic_identifier)
] @local.reference
