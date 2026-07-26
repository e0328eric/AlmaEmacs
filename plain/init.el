;;(when (eq system-type 'windows-nt)
;; (setenv "HOME" (concat "C:/Users/" (getenv "USERNAME"))))
;;(when (memq system-type '(gnu gnu/linux darwin))
;;  (setenv "HOME" (concat "/home/" (getenv "USER"))))
(when (eq system-type 'windows-nt)
  (setenv "HOME" (concat "C:/Users/almag")))
(when (memq system-type '(gnu gnu/linux darwin))
  (setenv "HOME" (concat "/home/almagest")))

(setq default-directory (expand-file-name "~/"))

;; melpa package settings
(require 'package)
(add-to-list 'package-archives
	     '("gnu" . "https://elpa.gnu.org/packages/") t)
(add-to-list 'package-archives
	     '("nongnu" . "https://elpa.nongnu.org/nongnu/") t)
(add-to-list 'package-archives
	     '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

;; Set platform-specific home config dir
(defconst my-home-config-dir
  (cond
   ((memq system-type '(windows-nt gnu gnu/linux darwin))
    (concat (getenv "HOME") "/.config/emacs/"))
   (t (getenv "HOME"))))

;; Derived paths
(setq custom-file (expand-file-name ".emacs.custom.el" my-home-config-dir))
(add-to-list 'load-path (expand-file-name ".emacs.local/" my-home-config-dir))
(add-to-list 'load-path (expand-file-name ".emacs.local/simpc-mode/" my-home-config-dir))
(setq backup-directory-alist
      `((".*" . ,(expand-file-name ".emacs.d/backups/" my-home-config-dir))))

;; default settings
(setq-default inhibit-splash-screen t)
(setq-default tab-width 4)
(setq-default display-line-numbers-type 'relative)
(setq-default visible-bell (eq system-type 'windows-nt))
(setq-default fill-column 80)
(setq-default auto-save-default nil) ; disable autosave
(setq-default scroll-margin 3) ; equivalence of scrolloff in vim
(global-display-fill-column-indicator-mode 0)
;; (add-to-list 'default-frame-alist '(fullscreen . maximized))

;; open new buffer with horizontal mode
(add-to-list 'display-buffer-alist
			 '("^\\*compilation\\*"
			   (display-buffer-reuse-window display-buffer-at-bottom)
			   (window-height . 0.3)))

(tool-bar-mode 0)
(menu-bar-mode 0)
(scroll-bar-mode 0)
(global-display-line-numbers-mode 1)

;; setting fonts
;; font_height == pixel * 10
(setq my/font-name "FiraCode Nerd Font Mono")
(setq my/font-size 110)
(defun my/apply-fonts (&optional _frame)
  (set-face-attribute 'default nil :family my/font-name :height my/font-size)
  (set-face-attribute 'fixed-pitch nil :family my/font-name :height my/font-size)
  (set-face-attribute 'variable-pitch nil :family my/font-name :height my/font-size)
  (set-fontset-font t 'hangul (font-spec :family "D2CodingLigature Nerd Font")))

(if (daemonp)
	(add-hook 'after-make-frame-functions #'my/apply-fonts)
  (my/apply-fonts))

;; UTF-8 "is" the standard!
;;(set-default-coding-systems 'utf-8)
;;(prefer-coding-system 'utf-8)

;; dired mode config
(setq dired-dwim-target t)
(setq dired-listing-switches "-alh")

;; utility functions
(defun add-newline-at-top ()
  (interactive)
  (beginning-of-line)
  (newline-and-indent)
  (previous-line))

(defun add-newline-at-bottom ()
  (interactive)
  (end-of-line)
  (newline-and-indent))

(defun forward-chunk ()
  "Forward to the end of the 'word at point' (vim-like)."
  (interactive)
  (skip-syntax-forward "-")
  (skip-syntax-forward "^-"))

(defun backward-chunk ()
  "Backward to the start of the 'word at point' (vim-like)."
  (interactive)
  (skip-syntax-backward "-")
  (skip-syntax-backward "^-"))


;; copied this function from here:
;; https://emacsredux.com/blog/2013/05/22/smarter-navigation-to-the-beginning-of-a-line/
(defun smarter-move-beginning-of-line (arg)
  "Move point back to indentation of beginning of line.

Move point to the first non-whitespace character on this line.
If point is already there, move to the beginning of the line.
Effectively toggle between the first non-whitespace character and
the beginning of the line.

If ARG is not nil or 1, move forward ARG - 1 lines first.  If
point reaches the beginning or end of the buffer, stop there."
  (interactive "^p")
  (setq arg (or arg 1))

  ;; Move lines first
  (when (/= arg 1)
    (let ((line-move-visual nil))
      (forward-line (1- arg))))

  (let ((orig-point (point)))
    (back-to-indentation)
    (when (= orig-point (point))
      (move-beginning-of-line 1))))

;; Keybindings
(global-unset-key (kbd "C-\\"))
(global-unset-key (kbd "M-\\"))
;;(global-unset-key (kbd "C-q")) ;; it is used in quoted-insert in default
(global-unset-key (kbd "C-z"))
(global-unset-key (kbd "C-x C-x"))
(global-set-key (kbd "<M-up>") 'scroll-down-command)
(global-set-key (kbd "<M-down>") 'scroll-up-command)
(global-set-key (kbd "<M-left>") 'smarter-move-beginning-of-line)
(global-set-key (kbd "<M-right>") 'move-end-of-line)
(global-set-key (kbd "<M-S-left>") 'backward-chunk)
(global-set-key (kbd "<M-S-right>") 'forward-chunk)
(global-set-key (kbd "C-\\") 'add-newline-at-top)
(global-set-key (kbd "M-\\") 'add-newline-at-bottom)
(global-set-key (kbd "C-x C-f") 'recentf-open)
(global-set-key (kbd "C-x C-.") 'find-file)
(global-set-key (kbd "C-x C-d") 'dired)
(global-set-key (kbd "C-x C-x") 'set-mark-command)

;; define ESC related keybindings (ESC-t is the prefix of the tremacs)
(global-set-key (kbd "<escape> c") 'compile)
(global-set-key (kbd "<escape> s") 'prettify-symbols-mode)
(global-set-key (kbd "<escape> a") 'auto-fill-mode)
(global-set-key (kbd "<escape> m") 'magit)
(global-set-key (kbd "<escape> b r") 'revert-buffer)
(global-set-key (kbd "<escape> f d") 'xref-find-definitions)
(global-set-key (kbd "<escape> f b") 'xref-go-back)
(global-set-key (kbd "<escape> f s") 'tags-search)
(global-set-key (kbd "<escape> f r") 'tags-query-replace)
(define-key key-translation-map (kbd "<escape> ESC") (kbd "C-g"))

(defun my-powershell-quote (text)
  "Quote TEXT as a PowerShell single-quoted string."
  (concat "'"
          (replace-regexp-in-string "'" "''" text t t)
          "'"))

(defun my-dired-set-current-owner-and-group ()
  "Set marked files' NTFS owner and group to the current Windows user."
  (interactive)
  (unless (eq system-type 'windows-nt)
    (user-error "This command only supports Windows"))
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this command from Dired"))

  (let* ((files (dired-get-marked-files))
         (file-list
          (mapconcat #'my-powershell-quote files ", "))
         (script
          (concat
           "$ErrorActionPreference = 'Stop'\n"
           "$user = "
           "[System.Security.Principal.WindowsIdentity]::GetCurrent().Name\n"
           "$identity = "
           "[System.Security.Principal.NTAccount]::new($user)\n"
           "$files = @(" file-list ")\n"
           "foreach ($file in $files) {\n"
           "  $acl = Get-Acl -LiteralPath $file\n"
           "  $acl.SetOwner($identity)\n"
           "  $acl.SetGroup($identity)\n"
           "  Set-Acl -LiteralPath $file -AclObject $acl\n"
           "}\n"))
         (encoded
          (base64-encode-string
           (encode-coding-string script 'utf-16le)
           t))
         (powershell
          (expand-file-name
           "System32/WindowsPowerShell/v1.0/powershell.exe"
           (getenv "WINDIR"))))

    (w32-shell-execute
     "runas"
     powershell
     (format "-NoProfile -NonInteractive -EncodedCommand %s"
             encoded))
    (message "Approve UAC; when finished, press g to refresh Dired")))

(with-eval-after-load 'dired
  (when (eq system-type 'windows-nt)
    (define-key dired-mode-map (kbd "O")
                #'my-dired-set-current-owner-and-group)))

;;===============================================================================
;;                               PACKAGE CONFIGS
;;===============================================================================
;; set the default mode for files
(require 'simpc-mode)
(require 'fasm-mode)
(require 'msgpack-mod)

(add-to-list 'auto-mode-alist '("\\.[hc]\\(pp\\)?\\'" . simpc-mode))
(add-to-list 'auto-mode-alist '("\\.tex\\'" . plain-TeX-mode))
(add-to-list 'auto-mode-alist '("\\.asm\\'" . fasm-mode))

;; vesti mode
(setq treesit-extra-load-path
	  (list (expand-file-name "tree-sitter" my-home-config-dir)
		(expand-file-name ".emacs-tree-sitter" my-home-config-dir)))
;(with-eval-after-load 'treesit
;  (add-to-list 'treesit-language-source-alist
;	       '(typst "https://github.com/uben0/tree-sitter-typst")))
(use-package lua-mode :ensure t)
(require 'vesti-ts-mode)

;; glosso mode
(require 'glosso-ts-mode)

;; lsp
(use-package lsp-mode
  :ensure t
  :init
  ;; set prefix for lsp-command-keymap
  (setq lsp-keymap-prefix "<escape> l")
  :hook (
         ;; Enable lsp-mode automatically when opening Zig files
         (zig-mode . lsp)
         ;; Optional: Enables which-key integration if you use the which-key package
         (lsp-mode . lsp-enable-which-key-integration))
  :commands lsp)

(use-package lsp-ui
  :ensure t
  :commands lsp-ui-mode
  :custom
  (lsp-ui-doc-enable t)
  (lsp-ui-sideline-enable t))

(use-package company
  :ensure t
  :init
  (global-company-mode 1)
  :config
  ;;(setq company-minimum-prefix-length 1
  ;;	company-idle-delay nil)
  (add-hook 'vesti-ts-mode-hook
        (lambda () (company-mode -1)))
  :bind
  ("C-x C-a" . company-complete))

(use-package rust-mode
  :ensure t
  :bind (:map rust-mode-map
              ;; Optional: Format buffer on save
              ("C-c C-f" . rust-format-buffer)))

(use-package zig-mode
  :ensure t
  :custom
  ;; Optional: Format buffer on save using 'zig fmt'
  (zig-format-on-save t))

(use-package typst-ts-mode
  :ensure t
  :mode "\\.typ\\'"
  :preface
  (defun my/typst-start-lsp ()
    "Start Typst LSP, preferring the binary downloaded by typst-ts-mode."
    (when (file-executable-p typst-ts-lsp-download-path)
      (setq-local lsp-typst-server-command
		  (list typst-ts-lsp-download-path)))
    (lsp))
  :hook (typst-ts-mode . my/typst-start-lsp))

(use-package odin-mode
  :vc (:url "https://github.com/mattt-b/odin-mode.git"
       :rev :newest)
  :mode "\\.odin\\'")

(use-package which-key
  :ensure t
  :config
  (which-key-mode)
  (which-key-setup-side-window-bottom))

(use-package smex
  :ensure t
  :bind
  (("M-x" . 'smex)
   ("M-X" . 'smex-major-mode-commands)
   ("C-c C-c M-x" . 'execute-extended-command)))

(use-package doom-themes
  :ensure t
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-moonlight t))

;; alternative for ido mode
(use-package ivy
  :ensure t
  :init
  (ivy-mode 1)
  (setq ivy-use-virtual-buffers t)
  (setq ivy-count-format "[%d/%d] "))

(use-package ace-window
  :ensure t
  :bind (("C-x o" . ace-window))
  :config
  (setq aw-scope 'frame))  ;; or 'global if you use multiple frames

;; magic git
(use-package magit
  :ensure t
  :pin melpa
  :bind
  (("C-x g" . magit-status)))

;; yasnippet
(setq my/yas-snippet-dirs (expand-file-name ".emacs.local/snippets" my-home-config-dir))
(add-to-list 'load-path
			 (expand-file-name ".emacs.d/plugins/yasnippet" my-home-config-dir))
(use-package yasnippet
  :ensure t
  :config
  (yas-global-mode 1)
  (setq yas-snippet-dirs (list my/yas-snippet-dirs))
  (define-key yas-minor-mode-map [(tab)] nil)
  (define-key yas-minor-mode-map (kbd "TAB") nil)
  (define-key yas-minor-mode-map (kbd "<tab>") nil)
  (yas-reload-all)
  :bind
  ("C-]" . #'yas-expand))

;; another great snippet pcakage
(require 'texmathp)
(use-package aas
  :ensure t
  :hook (latex-mode . aas-activate-for-major-mode)
  :hook (tex-mode . aas-activate-for-major-mode)
  :hook (vesti-ts-mode . aas-activate-for-major-mode)
  :config
  (aas-set-snippets 'vesti-ts-mode
	"MK"  (lambda () (interactive)
		    (yas-expand-snippet "\\$$1\\$$0")))
  (aas-set-snippets 'tex-mode
	"MK"  (lambda () (interactive)
		    (yas-expand-snippet "\\$$1\\$$0"))
	:cond #'texmathp ; expand only while in math
    ;; bind to functions!
    "//" (lambda () (interactive)
           (yas-expand-snippet "{$1 \\over $2}$0")))
  (aas-set-snippets 'latex-mode
	"MK"  (lambda () (interactive)
		    (yas-expand-snippet "\\$$1\\$$0"))
	:cond #'texmathp ; expand only while in math
    ;; bind to functions!
    "//" (lambda () (interactive)
           (yas-expand-snippet "\\frac{$1}{$2}$0")))
  ;; disable snippets by redefining them with a nil expansion
  (aas-set-snippets 'latex-mode
					"supp" nil))

(use-package multiple-cursors
  :ensure t
  :config
  (global-set-key (kbd "C-z C-l") 'mc/edit-lines)
  (global-set-key (kbd "C-z C-a") 'mc/mark-all-like-this)
  (global-set-key (kbd "C-z C-z") 'mc/mark-next-like-this-word)
  (global-set-key (kbd "<C-down>") 'mc/mark-next-like-this)
  (global-set-key (kbd "<C-up>") 'mc/mark-previous-like-this)
  (global-unset-key (kbd "M-<down-mouse-1>"))
  (global-set-key (kbd "M-<mouse-1>") 'mc/add-cursor-on-click))

(use-package rainbow-delimiters
  :ensure t
  :config
  (add-hook 'prog-mode-hook 'rainbow-delimiters-mode))

(use-package undo-tree
  :ensure t
  :config
  (global-undo-tree-mode)
  ;; Prevent undo tree files from polluting your git repo
  (setq undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo")))
  :bind
  ("C-x C-/" . 'undo-tree-redo))

