;;; glosso-ts-mode-tests.el --- Glosso highlighting tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with the matching Glosso parser in tree-sitter/:
;; emacs --batch -Q -L .emacs.local -l test/glosso-ts-mode-tests.el \
;;   -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'glosso-ts-mode)

(defmacro glosso-ts-test--with-buffer (text &rest body)
  "Parse and fontify TEXT, then evaluate BODY in its buffer."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (glosso-ts-mode)
     (font-lock-ensure)
     (should-not (treesit-node-check (treesit-buffer-root-node 'glosso)
                                    'has-error))
     ,@body))

(defun glosso-ts-test--face (text face &optional occurrence)
  "Check that OCCURRENCE of TEXT starts with FACE in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (search-forward text nil nil (or occurrence 1)))
    (should (eq (get-text-property (- (point) (length text)) 'face) face))))

(ert-deftest glosso-ts-highlights-types-and-calls ()
  (glosso-ts-test--with-buffer
      "Record :: struct { value: s64; }
Kind :: enum u8 { Ready; }
identity :: (argument: Record) -> Record { return argument; }
'%%' :: (value: s64) -> s64 #operator(suffix) { return value + value; }
main :: () { local := identity(.{ .value = 1 }); local.read(); number := 1.5; }
"
    (dotimes (index 3)
      (glosso-ts-test--face "Record" 'font-lock-type-face (1+ index)))
    (dolist (name '("Kind" "s64" "u8"))
      (glosso-ts-test--face name 'font-lock-type-face))
    (glosso-ts-test--face "Ready" 'font-lock-constant-face)
    (glosso-ts-test--face "identity" 'font-lock-function-name-face)
    (glosso-ts-test--face "identity" 'font-lock-function-name-face 2)
    (glosso-ts-test--face "read" 'font-lock-function-name-face)
    (glosso-ts-test--face "'%%'" 'font-lock-function-name-face)
    (glosso-ts-test--face "argument" 'font-lock-variable-name-face)
    (glosso-ts-test--face "argument" 'font-lock-variable-name-face 2)
    (glosso-ts-test--face "local" 'font-lock-variable-name-face)
    (glosso-ts-test--face "value" 'font-lock-variable-name-face)
    (glosso-ts-test--face "1.5" 'font-lock-constant-face)))

(ert-deftest glosso-ts-highlights-module-parameters-and-specialization ()
  (glosso-ts-test--with-buffer
      "#module_params(COUNT: ssize = 4, ENABLED := false);
#import \"Math\"(COUNT = COUNT) { parse, Tokens, Ops.'+' };
#export \"Core\"() {};
read :: (value: $T) -> s64
    #specialize #meaningful { T,,foo; } { return value.foo; }
LOCATION :: #source_location;
"
    (dolist (directive '("#module_params" "#import" "#export"
                         "#specialize" "#meaningful"))
      (glosso-ts-test--face directive 'font-lock-preprocessor-face))
    (glosso-ts-test--face "COUNT" 'font-lock-variable-name-face)
    (glosso-ts-test--face "ssize" 'font-lock-type-face)
    (glosso-ts-test--face "false" 'font-lock-constant-face)
    (glosso-ts-test--face "\"Math\"" 'font-lock-string-face)
    (glosso-ts-test--face "parse" 'font-lock-variable-name-face)
    (glosso-ts-test--face "Tokens" 'font-lock-type-face)
    (glosso-ts-test--face "Ops" 'font-lock-type-face)
    (glosso-ts-test--face "'+'" 'font-lock-builtin-face)
    (glosso-ts-test--face "foo" 'font-lock-variable-name-face)
    (glosso-ts-test--face "#source_location" 'font-lock-constant-face)))

(ert-deftest glosso-ts-highlights-receivers ()
  (glosso-ts-test--with-buffer
      "Record :: struct { value: s64; }
Record ::: {
    read :: (*const #self) -> s64 { return #self.value; }
    identity :: (#self) -> #Self_Type { return #self; }
}
"
    (glosso-ts-test--face "Record" 'font-lock-type-face 2)
    (glosso-ts-test--face "read" 'font-lock-function-name-face)
    (glosso-ts-test--face "const" 'font-lock-keyword-face)
    (dotimes (index 4)
      (glosso-ts-test--face "#self" 'font-lock-builtin-face (1+ index)))
    (glosso-ts-test--face "#Self_Type" 'font-lock-type-face)))

(ert-deftest glosso-ts-highlights-nested-comments-and-edits ()
  (glosso-ts-test--with-buffer
      "main :: () { /* outer /* inner */ still a comment */ print(c\"ok\"); }
"
    (glosso-ts-test--face "outer" 'font-lock-comment-face)
    (glosso-ts-test--face "inner" 'font-lock-comment-face)
    (glosso-ts-test--face "still a comment" 'font-lock-comment-face)
    (glosso-ts-test--face "print" 'font-lock-function-name-face)
    (glosso-ts-test--face "c\"ok\"" 'font-lock-string-face)
    (goto-char (point-min))
    (search-forward "print")
    (replace-match "display" t t)
    (font-lock-flush)
    (font-lock-ensure)
    (glosso-ts-test--face "display" 'font-lock-function-name-face)
    (glosso-ts-test--face "still a comment" 'font-lock-comment-face)))

(ert-deftest glosso-ts-builtin-predicate-matches-exact-names ()
  (glosso-ts-test--with-buffer
      "a: ssize; b: ssizex; c: Namespace; d: namespace; e: s64;"
    (let* ((glosso-ts-mode--capture-faces '(("type.builtin" . "builtin")))
           (captures (treesit-query-capture
                      (treesit-buffer-root-node 'glosso)
                      (glosso-ts-mode--font-lock-query)))
           (builtins (delq nil (mapcar
                                (lambda (capture)
                                  (when (eq (car capture) 'builtin)
                                    (treesit-node-text (cdr capture))))
                                captures))))
      (should (equal builtins '("ssize" "Namespace" "s64"))))))

(provide 'glosso-ts-mode-tests)
;;; glosso-ts-mode-tests.el ends here
