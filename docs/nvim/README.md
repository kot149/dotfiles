# Neovim 使い方ガイド

VSCodeライクなキーバインドに設定されたNeovimの操作ガイドです。

## 目次

- [基本概念: モード](./modes.md)
- [カーソル移動](./navigation.md)
- [テキスト編集](./editing.md)
- [ファイル・バッファ操作](./files.md)
- [検索・置換](./search.md)
- [コード補助 (LSP)](./lsp.md)
- [キーバインド一覧](./keymaps.md)

## 最初の1週間で覚えるべき最小セット

| キー | 動作 |
|------|------|
| `Esc` | ノーマルモードに戻る（迷ったらこれ） |
| `i` | 挿入モード（文字を書く） |
| `Ctrl+S` | 保存 |
| `Ctrl+P` | ファイルを開く |
| `Ctrl+B` | エクスプローラを開閉 |
| `u` | アンドゥ |
| `V` → `y` → `p` | 行をコピーして貼り付け |
| `Ctrl+/` | コメントをトグル |

## インストール済みプラグイン概要

| プラグイン | 役割 | VSCode相当 |
|-----------|------|-----------|
| [lazy.nvim](https://github.com/folke/lazy.nvim) | プラグインマネージャ | Extensions |
| [Telescope](https://github.com/nvim-telescope/telescope.nvim) | ファジーファインダー | Quick Open / Search |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | シンタックスハイライト | 組み込み |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSPクライアント | 組み込み |
| [mason.nvim](https://github.com/williamboman/mason.nvim) | LSPサーバー管理 | Extensions |
| [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | コード補完 | 組み込み |
| [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | ファイルエクスプローラ | Explorer |
| [catppuccin](https://github.com/catppuccin/nvim) | カラースキーム | テーマ |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | ステータスライン | ステータスバー |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Gitサイン | GitLens |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | フォーマッタ | Format Document |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | 診断リスト | Problems パネル |
