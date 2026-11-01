;;; glosso-ts-mode.el --- Tree-sitter support for Glosso -*- lexical-binding: t; -*-

;; Author: AlmaEmacs contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages tree-sitter glosso

;;; Commentary:

;; Major mode for editing Glosso files (.glo), powered by Emacs's built-in
;; Tree-sitter support.
;;
;; The Tree-sitter grammar must be installed as
;; `libtree-sitter-glosso.dll', `libtree-sitter-glosso.so', or
;; `libtree-sitter-glosso.dylib'.  It can be placed in one of the directories
;; in `treesit-extra-load-path'.  When this mode is loaded from the usual
;; `.emacs.local' directory, a sibling `tree-sitter' directory is also used
;; automatically when it contains the Glosso grammar.
;;
;; The query in `glosso/highlights.scm' is kept separate so it can also be
;; shared by other Tree-sitter clients.  Its predicates and semantic capture
;; names are adapted for Emacs font-lock when the mode is initialized.

;;; Code:

(require 'treesit)

(defgroup glosso-ts nil
  "Major mode for Glosso files using Tree-sitter."
  :group 'languages
  :prefix "glosso-ts-")

(defconst glosso-ts-mode--directory
  (file-name-directory
   (or load-file-name
       (locate-library "glosso-ts-mode")
       default-directory))
  "Directory containing `glosso-ts-mode.el'.")

(defcustom glosso-ts-mode-highlights-file
  (expand-file-name "glosso/highlights.scm" glosso-ts-mode--directory)
  "Tree-sitter highlight query used by `glosso-ts-mode'."
  :type 'file
  :group 'glosso-ts)

(defcustom glosso-ts-mode-indent-offset 4
  "Number of spaces used for each Glosso indentation step."
  :type 'natnum
  :group 'glosso-ts)

;; These are the capture names used by highlights.scm.  The values are
;; strings because they become Tree-sitter query capture names.  Generic
;; captures use callbacks so they cannot overwrite more specific faces.
(defconst glosso-ts-mode--capture-faces
  '(("keyword" . "font-lock-keyword-face")
    ("attribute" . "font-lock-preprocessor-face")
    ("comment" . "font-lock-comment-face")
    ("string" . "font-lock-string-face")
    ("character" . "font-lock-string-face")
    ("number" . "font-lock-constant-face")
    ("number.float" . "font-lock-constant-face")
    ("boolean" . "font-lock-constant-face")
    ("constant.builtin" . "font-lock-constant-face")
    ("type" . "font-lock-type-face")
    ("type.definition" . "font-lock-type-face")
    ("type.builtin" . "font-lock-type-face")
    ("variable.builtin" . "font-lock-builtin-face")
    ("variable.parameter" . "font-lock-variable-name-face")
    ("function" . "font-lock-function-name-face")
    ("function.call" . "font-lock-function-name-face")
    ("function.method.call" . "font-lock-function-name-face")
    ("property" . "glosso-ts-mode--fontify-variable")
    ("constant" . "font-lock-constant-face")
    ("variable" . "glosso-ts-mode--fontify-variable")
    ("label" . "font-lock-constant-face")
    ("operator" . "glosso-ts-mode--fontify-operator"))
  "Mapping from Glosso query captures to faces or fontification functions.")

(defun glosso-ts-mode--fontify-fallback (face node start end)
  "Apply FACE to NODE between START and END where no face is present."
  (let ((beg (max start (treesit-node-start node)))
        (end (min end (treesit-node-end node))))
    (when (< beg end)
      (treesit-fontify-with-override beg end face 'keep))))

(defun glosso-ts-mode--fontify-variable (node _override start end &rest _)
  "Fontify NODE as a fallback variable between START and END."
  (glosso-ts-mode--fontify-fallback
   'font-lock-variable-name-face node start end))

(defun glosso-ts-mode--fontify-operator (node _override start end &rest _)
  "Fontify NODE as a fallback operator between START and END."
  (glosso-ts-mode--fontify-fallback
   'font-lock-builtin-face node start end))

(defun glosso-ts-mode--font-lock-query ()
  "Read and adapt `glosso-ts-mode-highlights-file' for Emacs font-lock."
  (unless (file-readable-p glosso-ts-mode-highlights-file)
    (error "Glosso highlight query not found: %s"
           glosso-ts-mode-highlights-file))
  (with-temp-buffer
    (insert-file-contents glosso-ts-mode-highlights-file)
    ;; Emacs supports #match?, but not the CLI's #any-of? predicate.
    ;; Read its string arguments and build an exact, case-sensitive match.
    (goto-char (point-min))
    (while (re-search-forward "(#any-of\\?\\s-+\\(@[[:alnum:]_.-]+\\)" nil t)
      (let ((start (match-beginning 0))
            (capture (match-string 1))
            (values nil))
        (skip-chars-forward " \t\r\n")
        (while (eq (char-after) ?\")
          (push (read (current-buffer)) values)
          (skip-chars-forward " \t\r\n"))
        (unless (and values (eq (char-after) ?\)))
          (error "Invalid #any-of? predicate in Glosso highlight query"))
        (delete-region start (1+ (point)))
        (insert (format "(#match? %s %S)" capture
                        (concat "\\`" (regexp-opt values) "\\'")))))
    (replace-regexp-in-string
     "@\\([[:alnum:]_.-]+\\)"
     (lambda (capture)
       (let ((face (cdr (assoc (substring capture 1)
                               glosso-ts-mode--capture-faces))))
         (if face
             (concat "@" face)
           ;; Leave unknown captures intact.  This makes it possible to add
           ;; non-font-lock captures to highlights.scm without breaking the
           ;; mode; Emacs simply ignores captures that are not faces or
           ;; functions.
           capture)))
     (buffer-string)
     t)))

(defun glosso-ts-mode--add-local-grammar-path ()
  "Add the conventional sibling `tree-sitter' directory when available."
  (let ((directory
         (expand-file-name "../tree-sitter/" glosso-ts-mode--directory)))
    (when (and (file-directory-p directory)
               (directory-files
                directory nil
                "\\`libtree-sitter-glosso\\.\\(?:dll\\|so\\|dylib\\)\\'"))
      (add-to-list 'treesit-extra-load-path directory))))

;;; Indentation

(defvar glosso-ts-mode--indent-rules
  `((glosso
     ((parent-is "source_file") column-0 0)
     ((node-is "}") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((parent-is "declaration_block") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "block") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "code_block") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "string_block") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "pattern_arm_block") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "struct_declaration") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "enum_declaration") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "enum_flags_declaration") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "union_declaration") parent-bol glosso-ts-mode-indent-offset)
     ((parent-is "function_declaration") parent-bol glosso-ts-mode-indent-offset)
     (no-node prev-line 0)
     (catch-all prev-line 0)))
  "Tree-sitter indentation rules for `glosso-ts-mode'.")

;;;###autoload
(define-derived-mode glosso-ts-mode prog-mode "Glosso"
  "Major mode for editing Glosso files, powered by Tree-sitter.

This mode requires the Glosso Tree-sitter grammar and `glosso/highlights.scm'.
The grammar language name is `glosso'.

\\{glosso-ts-mode-map}"
  (glosso-ts-mode--add-local-grammar-path)
  (unless (treesit-ready-p 'glosso)
    (error "Tree-sitter grammar for Glosso is unavailable or incompatible; install/rebuild libtree-sitter-glosso for ABI %d"
           (treesit-library-abi-version)))

  (treesit-parser-create 'glosso)

  (setq-local indent-tabs-mode nil)
  (setq-local tab-width glosso-ts-mode-indent-offset)

  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//+\\s-*")

  (setq-local treesit-font-lock-settings
              (treesit-font-lock-rules
               :language 'glosso
               :feature 'highlights
               ;; Specific captures supersede fallback identifier/operator faces.
               :override t
               (glosso-ts-mode--font-lock-query)))
  (setq-local treesit-font-lock-feature-list '((highlights)))

  (setq-local treesit-simple-indent-rules glosso-ts-mode--indent-rules)
  (setq-local indent-line-function #'treesit-indent)

  (treesit-major-mode-setup))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.glo\\'" . glosso-ts-mode))

(provide 'glosso-ts-mode)
;;; glosso-ts-mode.el ends here
