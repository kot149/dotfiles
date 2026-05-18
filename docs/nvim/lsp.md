# コード補助 (LSP)

LSP (Language Server Protocol) はコードの補完・エラー検出・定義ジャンプなどを提供します。  
VSCodeの組み込み言語サポートと同等の機能です。

## コード補完

挿入モードで文字を入力すると自動的に補完候補が表示されます。

| キー | 動作 |
|------|------|
| `Ctrl+Space` | 補完を明示的に起動 |
| `Tab` / `Shift+Tab` | 候補リストの上下移動 |
| `Ctrl+N` / `Ctrl+P` | 候補リストの上下移動（代替） |
| `Enter` | 候補を確定 |
| `Ctrl+E` | 補完ウィンドウを閉じる |

## 定義・参照へのジャンプ

| キー | 動作 | VSCode相当 |
|------|------|-----------|
| `F12` | 定義へジャンプ | F12 |
| `Ctrl+O` | ジャンプ前の位置に戻る | Alt+← |
| `K` | カーソル下のシンボルのドキュメントを表示 | Ctrl+K Ctrl+I |

## シンボル操作

| キー | 動作 | VSCode相当 |
|------|------|-----------|
| `F2` | シンボルをリネーム | F2 |
| `Ctrl+Shift+.` | コードアクション（クイックフィックス） | Ctrl+. |
| `<leader>.` | コードアクション（代替） | Ctrl+. |

> `<leader>` はスペースキーです。

## 診断（エラー・警告）

ファイル内のエラーや警告は行のサイドに表示され、カーソルを合わせると詳細が出ます。

| キー | 動作 | VSCode相当 |
|------|------|-----------|
| `Ctrl+Shift+M` | Problems パネルを開閉 | Ctrl+Shift+M |
| `<leader>xx` | 診断リストを開閉 | — |

### 診断サイン（行の左端に表示されるマーク）

| マーク | 意味 |
|-------|------|
| `E` | エラー (Error) |
| `W` | 警告 (Warning) |
| `I` | 情報 (Information) |
| `H` | ヒント (Hint) |

## フォーマット

| キー | 動作 | VSCode相当 |
|------|------|-----------|
| `Shift+Alt+F` | ドキュメントをフォーマット | Shift+Alt+F |

保存時にも自動でフォーマットが実行されます（`format_on_save`設定済み）。

対応しているフォーマッタ:

| 言語 | フォーマッタ |
|------|------------|
| Lua | stylua |
| Nix | nixpkgs-fmt |
| JS/TS/TSX | prettier |
| HTML/CSS/JSON | prettier |
| Python | ruff |
| Go | gofmt |
| Rust | rustfmt |

## LSPサーバーの管理

`:Mason` コマンドでLSPサーバーのインストール・管理UIが開きます。

| キー（Mason UI内） | 動作 |
|------------------|------|
| `i` | LSPサーバーをインストール |
| `u` | アップデート |
| `X` | アンインストール |
| `q` | 閉じる |

### nix管理のLSP（Masonを使わず自動で使える）

| LSPサーバー | 言語 |
|------------|------|
| `lua-language-server` | Lua |
| `nil` | Nix |

### Mason管理のLSP（初回起動時に`:Mason`からインストール）

| LSPサーバー | 言語 |
|------------|------|
| `ts_ls` | TypeScript / JavaScript |
| `eslint` | TypeScript / JavaScript（リント） |
| `html` | HTML |
| `cssls` | CSS |
| `jsonls` | JSON |
| `pyright` | Python |
| `gopls` | Go |
| `rust_analyzer` | Rust |
| `bashls` | Bash |
| `yamlls` | YAML |
