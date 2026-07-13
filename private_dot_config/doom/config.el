;;; config.el -*- lexical-binding: t; -*-
;; VSCode-like Doom Emacs

(setq user-full-name "kota-takeuchi"
      user-mail-address "kota.takeuchi@geniee.co.jp")

;;; Look & feel
(setq doom-theme 'vscode-dark-plus)
(setq display-line-numbers-type t)
(setq doom-font (font-spec :family "Inconsolata Nerd Font" :size 14)
      doom-variable-pitch-font (font-spec :family "Inconsolata Nerd Font" :size 14))

;; Frame chrome closer to VSCode
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark))
(setq frame-title-format '("%b — Emacs"))
(setq inhibit-startup-screen t)
(setq confirm-kill-emacs nil)

;; Show column, matching parens, smoother scroll
(column-number-mode +1)
(show-paren-mode +1)
(setq scroll-margin 3
      scroll-conservatively 101
      mouse-wheel-progressive-speed nil)

;; Auto-revert (like VSCode auto-reload on external change)
(global-auto-revert-mode +1)
(setq auto-revert-verbose nil
      global-auto-revert-non-file-buffers t)

;; Save cursor position across sessions
(save-place-mode +1)

;; UTF-8 everywhere
(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)

;;; VSCode-style CUA behavior (Ctrl+C/V/X/Z, shift-select)
(cua-mode +1)
(setq cua-keep-region-after-copy t)
(delete-selection-mode +1)
(transient-mark-mode +1)

;;; macOS modifiers — Cmd = super, Option = meta
(when (eq system-type 'darwin)
  (setq mac-command-modifier 'super
        mac-option-modifier 'meta
        mac-right-option-modifier 'none
        ns-command-modifier 'super
        ns-option-modifier 'meta
        ns-right-option-modifier 'none))

;;; VSCode-like keybindings (Cmd = ⌘, i.e. `s-`)
(map! ;; File / project
      "s-p"   #'projectile-find-file            ;; Cmd+P  quick open
      "s-P"   #'execute-extended-command        ;; Cmd+Shift+P  command palette
      "M-x"   #'execute-extended-command
      "s-s"   #'save-buffer                     ;; Cmd+S
      "s-S"   #'save-some-buffers               ;; Cmd+Shift+S save all
      "s-o"   #'find-file                       ;; Cmd+O
      "s-n"   #'make-frame-command              ;; Cmd+N new window
      "s-N"   #'+default/new-buffer             ;; Cmd+Shift+N new untitled
      "s-w"   #'kill-current-buffer             ;; Cmd+W close tab
      "s-q"   #'save-buffers-kill-terminal      ;; Cmd+Q quit

      ;; Editing
      "s-a"   #'mark-whole-buffer               ;; Cmd+A
      "s-z"   #'undo                            ;; Cmd+Z
      "s-Z"   #'undo-redo                       ;; Cmd+Shift+Z
      "s-x"   #'kill-region                     ;; Cmd+X
      "s-c"   #'kill-ring-save                  ;; Cmd+C
      "s-v"   #'yank                            ;; Cmd+V
      "s-/"   #'comment-line                    ;; Cmd+/  toggle line comment
      "s-]"   #'indent-rigidly-right-to-tab-stop
      "s-["   #'indent-rigidly-left-to-tab-stop
      "s-d"   #'symbol-overlay-put              ;; Cmd+D highlight (multi-cursor-lite)
      "M-<up>"    #'move-text-up                ;; Alt+Up   move line up
      "M-<down>"  #'move-text-down              ;; Alt+Down move line down
      "s-<up>"    #'beginning-of-buffer
      "s-<down>"  #'end-of-buffer
      "s-<left>"  #'move-beginning-of-line
      "s-<right>" #'move-end-of-line
      "s-l"   #'goto-line                       ;; Cmd+G is next search, Cmd+L go-to-line
      "s-g"   #'isearch-repeat-forward
      "s-G"   #'isearch-repeat-backward

      ;; Search
      "s-f"   #'consult-line                    ;; Cmd+F find in file
      "s-F"   #'+default/search-project         ;; Cmd+Shift+F search in project
      "s-h"   #'query-replace                   ;; Cmd+H replace

      ;; Tabs / buffers (Ctrl+Tab like VSCode)
      "C-<tab>"       #'next-buffer
      "C-S-<tab>"     #'previous-buffer
      "s-{"           #'previous-buffer
      "s-}"           #'next-buffer
      "s-1"           (cmd! (+workspace/switch-to 0))
      "s-2"           (cmd! (+workspace/switch-to 1))
      "s-3"           (cmd! (+workspace/switch-to 2))
      "s-4"           (cmd! (+workspace/switch-to 3))
      "s-5"           (cmd! (+workspace/switch-to 4))
      "s-t"           #'+workspace/new
      "s-T"           #'+workspace/switch-to-final

      ;; Sidebar & panel (VSCode-style smart toggle)
      "s-b"   #'+my/treemacs-smart-toggle       ;; Cmd+B: closed→open+focus / editor→focus sidebar / sidebar→close
      "s-`"   #'+vterm/toggle                   ;; Cmd+` integrated terminal
      "s-j"   #'+vterm/toggle
      "s-e"   #'+my/treemacs-smart-toggle       ;; Cmd+E explorer

      ;; LSP / navigation (VSCode-style F-keys)
      "<f2>"       #'lsp-rename
      "<f12>"      #'+lookup/definition
      "S-<f12>"    #'+lookup/references
      "M-<f12>"    #'+lookup/implementations
      "C-."        #'lsp-execute-code-action    ;; Ctrl+.  quick fix
      "M-."        #'+lookup/definition
      "M-,"        #'better-jumper-jump-backward
      "s-,"        (cmd! (find-file "~/.config/doom/config.el"))

      ;; Split
      "s-\\"  #'evil-window-vsplit-or-split
      "C-\\"  #'split-window-right)

;; Fallback for non-mac terminals: Ctrl-C/V/X/Z via cua-mode already; add Ctrl+P etc.
(map! "C-p" #'projectile-find-file
      "C-S-p" #'execute-extended-command
      "C-S-f" #'+default/search-project
      "C-b"   #'+my/treemacs-smart-toggle
      "C-`"   #'+vterm/toggle)

;;; UX niceties
(after! projectile
  (setq projectile-project-search-path '("~/dev/" "~/work/" "~/.local/share/chezmoi/"))
  (setq projectile-sort-order 'recently-active))

(defun +my/treemacs-smart-toggle ()
  "VSCode-like sidebar toggle:
- If treemacs window is not visible: open it and focus it.
- If visible and current buffer is NOT treemacs: focus the treemacs window.
- If visible and current buffer IS treemacs: close the sidebar."
  (interactive)
  (require 'treemacs)
  (let ((win (treemacs-get-local-window)))
    (cond
     ((null win)
      (treemacs-select-window))
     ((not (eq (selected-window) win))
      (select-window win))
     (t
      (treemacs-quit)))))

(after! treemacs
  (setq treemacs-width 32
        treemacs-follow-mode t
        treemacs-filewatch-mode t
        treemacs-git-mode 'deferred
        treemacs-is-never-other-window t
        treemacs-position 'left))

;; Auto-open treemacs on startup (VSCode-like)
(add-hook 'emacs-startup-hook
          (lambda ()
            (require 'treemacs)
            (treemacs)
            (other-window 1))
          'append)

(after! company
  (setq company-idle-delay 0.1
        company-minimum-prefix-length 1
        company-selection-wrap-around t))

(after! lsp-mode
  (setq lsp-headerline-breadcrumb-enable t
        lsp-modeline-code-actions-enable t
        lsp-signature-auto-activate t
        lsp-signature-render-documentation t
        lsp-enable-snippet t))

(after! lsp-ui
  (setq lsp-ui-doc-enable t
        lsp-ui-doc-show-with-cursor t
        lsp-ui-doc-delay 0.5
        lsp-ui-sideline-enable t
        lsp-ui-sideline-show-code-actions t
        lsp-ui-sideline-show-hover nil))

(after! magit
  (setq magit-diff-refine-hunk 'all))

;; symbol-overlay quick-highlight, VSCode Cmd+D-ish
(use-package! symbol-overlay
  :defer t
  :init
  (setq symbol-overlay-idle-time 0.2))

;; Move-text bindings (used by keymap above)
(use-package! move-text
  :defer t)

;; Prefer LF, always trailing newline
(setq require-final-newline t)
(setq-default indent-tabs-mode nil
              tab-width 2)

;; Format-on-save is enabled by :editor format +onsave; make it explicit
(after! apheleia
  (apheleia-global-mode +1))
