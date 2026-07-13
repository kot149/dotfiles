;;; init.el -*- lexical-binding: t; -*-
;; VSCode-like Doom Emacs (no evil)

(doom! :input

       :completion
       (company +childframe)
       (vertico +icons)

       :ui
       doom
       doom-dashboard
       (emoji +unicode)
       hl-todo
       indent-guides
       ligatures
       modeline
       nav-flash
       ophints
       (popup +defaults)
       tabs
       treemacs
       (vc-gutter +pretty)
       vi-tilde-fringe
       window-select
       workspaces

       :editor
       (format +onsave)
       file-templates
       fold
       multiple-cursors
       snippets

       :emacs
       (dired +icons)
       electric
       (ibuffer +icons)
       (undo +tree)
       vc

       :term
       vterm

       :checkers
       syntax
       (spell +flyspell)
       grammar

       :tools
       (debugger +lsp)
       direnv
       docker
       editorconfig
       (eval +overlay)
       lookup
       lsp
       magit
       make
       pass
       tree-sitter

       :os
       (:if IS-MAC macos)

       :lang
       emacs-lisp
       (go +lsp)
       (javascript +lsp +tree-sitter)
       (json +lsp)
       markdown
       nix
       org
       (python +lsp)
       (rust +lsp +tree-sitter)
       sh
       (typescript +lsp +tree-sitter)
       web
       yaml

       :config
       (default +bindings +smartparens))
