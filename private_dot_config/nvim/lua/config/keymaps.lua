local map = vim.keymap.set
local o = { noremap = true, silent = true }

-- ============================================================
-- ファイル操作
-- ============================================================

-- Ctrl+S: 保存
map({ "n", "i", "v" }, "<C-s>", "<Cmd>w<CR>", { noremap = true, silent = true, desc = "Save file" })

-- Ctrl+W: タブ/バッファを閉じる (ウィンドウ操作は C-hjkl で代替)
map("n", "<C-w>", "<Cmd>bdelete<CR>", { noremap = true, silent = true, desc = "Close buffer" })

-- ============================================================
-- 検索・Quick Open
-- ============================================================

-- Ctrl+P: Quick Open (ファイル検索)
map("n", "<C-p>", "<Cmd>Telescope find_files<CR>", { noremap = true, silent = true, desc = "Quick Open" })

-- Ctrl+Shift+P: コマンドパレット
map("n", "<C-S-p>", "<Cmd>Telescope commands<CR>", { noremap = true, silent = true, desc = "Command Palette" })

-- Ctrl+F: ファイル内検索
map("n", "<C-f>", "/", { noremap = true, desc = "Find in file" })

-- Ctrl+H: 検索と置換
map("n", "<C-h>", ":%s/", { noremap = true, desc = "Find and Replace" })

-- Ctrl+Shift+F: ワークスペース全体検索
map("n", "<C-S-f>", "<Cmd>Telescope live_grep<CR>", { noremap = true, silent = true, desc = "Find in Files" })

-- Ctrl+Shift+E: エクスプローラにフォーカス
map("n", "<C-S-e>", "<Cmd>Neotree focus<CR>", { noremap = true, silent = true, desc = "Focus Explorer" })

-- ============================================================
-- コメントトグル (Ctrl+/)
-- ターミナルでは Ctrl+/ が C-_ として送られることがある
-- ============================================================

local function toggle_comment_line()
  require("Comment.api").toggle.linewise.current()
end

local function toggle_comment_visual()
  local esc = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
  require("Comment.api").toggle.linewise(vim.fn.visualmode())
end

map("n", "<C-/>", toggle_comment_line, { noremap = true, desc = "Toggle Comment" })
map("i", "<C-/>", toggle_comment_line, { noremap = true, desc = "Toggle Comment" })
map("v", "<C-/>", toggle_comment_visual, { noremap = true, desc = "Toggle Comment" })
-- Ctrl+/ が C-_ として届くターミナル向け
map("n", "<C-_>", toggle_comment_line, { noremap = true, silent = true })
map("i", "<C-_>", toggle_comment_line, { noremap = true, silent = true })
map("v", "<C-_>", toggle_comment_visual, { noremap = true, silent = true })

-- ============================================================
-- 行の移動 (Alt+↑/↓)
-- ============================================================

map("n", "<M-Up>",   "<Cmd>m .-2<CR>==",       { noremap = true, silent = true, desc = "Move Line Up" })
map("n", "<M-Down>", "<Cmd>m .+1<CR>==",        { noremap = true, silent = true, desc = "Move Line Down" })
map("i", "<M-Up>",   "<Esc><Cmd>m .-2<CR>==gi", { noremap = true, silent = true, desc = "Move Line Up" })
map("i", "<M-Down>", "<Esc><Cmd>m .+1<CR>==gi", { noremap = true, silent = true, desc = "Move Line Down" })
map("v", "<M-Up>",   ":m '<-2<CR>gv=gv",        { noremap = true, silent = true, desc = "Move Selection Up" })
map("v", "<M-Down>", ":m '>+1<CR>gv=gv",        { noremap = true, silent = true, desc = "Move Selection Down" })

-- ============================================================
-- 行のコピー (Alt+Shift+↑/↓)
-- ============================================================

map("n", "<M-S-Up>",   "<Cmd>t .-1<CR>",  { noremap = true, silent = true, desc = "Copy Line Up" })
map("n", "<M-S-Down>", "<Cmd>t .<CR>",    { noremap = true, silent = true, desc = "Copy Line Down" })
map("i", "<M-S-Up>",   "<Esc><Cmd>t .-1<CR>gi", { noremap = true, silent = true, desc = "Copy Line Up" })
map("i", "<M-S-Down>", "<Esc><Cmd>t .<CR>gi",   { noremap = true, silent = true, desc = "Copy Line Down" })
-- ビジュアル選択範囲をコピー: :t'> で末尾の次へ、:t'<-1 で先頭の前へ
map("v", "<M-S-Down>", ":t'><CR>gv",   { noremap = true, silent = true, desc = "Copy Selection Down" })
map("v", "<M-S-Up>",   ":t'<-1<CR>gv", { noremap = true, silent = true, desc = "Copy Selection Up" })

-- ============================================================
-- 行削除 (Ctrl+Shift+K)
-- ============================================================

map({ "n", "i" }, "<C-S-k>", "<Cmd>normal! dd<CR>", { noremap = true, silent = true, desc = "Delete Line" })

-- ============================================================
-- 行を挿入 (Ctrl+Enter / Ctrl+Shift+Enter)
-- ============================================================

map("n", "<C-CR>",   "o<Esc>",  { noremap = true, desc = "Insert Line Below" })
map("i", "<C-CR>",   "<Esc>o",  { noremap = true, desc = "Insert Line Below" })
map("n", "<C-S-CR>", "O<Esc>",  { noremap = true, desc = "Insert Line Above" })
map("i", "<C-S-CR>", "<Esc>O",  { noremap = true, desc = "Insert Line Above" })

-- ============================================================
-- インデント (Tab / Shift+Tab in visual, Ctrl+] / Ctrl+[)
-- ============================================================

map("v", "<Tab>",   ">gv", { noremap = true, desc = "Indent" })
map("v", "<S-Tab>", "<gv", { noremap = true, desc = "Outdent" })

-- ============================================================
-- LSP (F2/F12 は VSCode 標準)
-- ============================================================

map("n", "<F2>",  vim.lsp.buf.rename,      { noremap = true, desc = "Rename Symbol" })
map("n", "<F12>", vim.lsp.buf.definition,  { noremap = true, desc = "Go to Definition" })
map("n", "K",     vim.lsp.buf.hover,       { noremap = true, desc = "Hover Documentation" })
map("n", "<C-S-period>", vim.lsp.buf.code_action, { noremap = true, silent = true, desc = "Code Action (Ctrl+.)" })
-- ターミナルで Ctrl+. が届かない場合の代替
map({ "n", "v" }, "<leader>.", vim.lsp.buf.code_action, { noremap = true, desc = "Code Action" })

-- ============================================================
-- タブ/バッファ切り替え (Ctrl+Tab / Ctrl+Shift+Tab)
-- ============================================================

map("n", "<C-Tab>",   "<Cmd>bnext<CR>",     { noremap = true, silent = true, desc = "Next Buffer" })
map("n", "<C-S-Tab>", "<Cmd>bprevious<CR>", { noremap = true, silent = true, desc = "Prev Buffer" })

-- ============================================================
-- サイドバー・パネル
-- ============================================================

-- Ctrl+B: エクスプローラのトグル
map("n", "<C-b>", "<Cmd>Neotree toggle<CR>", { noremap = true, silent = true, desc = "Toggle Explorer" })

-- Ctrl+`: 統合ターミナルのトグル
local term_buf = -1
local function toggle_terminal()
  if term_buf ~= -1 and vim.api.nvim_buf_is_valid(term_buf) then
    local win = vim.fn.bufwinid(term_buf)
    if win ~= -1 then
      vim.api.nvim_win_close(win, false)
      return
    end
  end
  vim.cmd("botright 15split")
  if term_buf ~= -1 and vim.api.nvim_buf_is_valid(term_buf) then
    vim.api.nvim_set_current_buf(term_buf)
  else
    vim.cmd("terminal")
    term_buf = vim.api.nvim_get_current_buf()
  end
  vim.cmd("startinsert")
end

map("n", "<C-`>", toggle_terminal, { noremap = true, silent = true, desc = "Toggle Terminal" })
map("t", "<C-`>", toggle_terminal, { noremap = true, silent = true, desc = "Toggle Terminal" })
-- ターミナルモードから Escape で抜ける
map("t", "<Esc>", "<C-\\><C-n>", { noremap = true, desc = "Exit Terminal Mode" })

-- ============================================================
-- ウィンドウ分割・移動
-- ============================================================

map("n", "<C-\\>", "<Cmd>vsplit<CR>", { noremap = true, silent = true, desc = "Split Right" })
-- ウィンドウ間の移動 (C-w の代替。C-w はバッファ閉じるに使用)
map("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })
map("n", "<C-j>", "<C-w>j", { noremap = true, silent = true })
map("n", "<C-k>", "<C-w>k", { noremap = true, silent = true })
map("n", "<C-l>", "<C-w>l", { noremap = true, silent = true })

-- ============================================================
-- Go to Line (Ctrl+G)
-- ============================================================

map("n", "<C-g>", function()
  local line = vim.fn.input("Go to line: ")
  if line ~= "" then
    vim.cmd(line)
  end
end, { noremap = true, desc = "Go to Line" })

-- ============================================================
-- 検索ハイライトのクリア
-- ============================================================

map("n", "<Esc>", "<Cmd>nohlsearch<CR>", o)
