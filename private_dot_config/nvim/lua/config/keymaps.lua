local map = vim.keymap.set
local o = { noremap = true, silent = true }

-- ============================================================
-- Undo / Redo
-- ============================================================

-- Ctrl+Z: Undo
map("n", "<C-z>", "u",            { noremap = true, silent = true, desc = "Undo" })
map("i", "<C-z>", "<C-o>u",       { noremap = true, silent = true, desc = "Undo" })
map("v", "<C-z>", "<Esc>u",       { noremap = true, silent = true, desc = "Undo" })

-- Ctrl+Y: Redo
map("n", "<C-y>", "<C-r>",      { noremap = true, silent = true, desc = "Redo" })
map("i", "<C-y>", "<C-o><C-r>", { noremap = true, silent = true, desc = "Redo" })

-- ============================================================
-- コピー・ペースト (VSCode 風)
-- ============================================================

-- Ctrl+C: ビジュアル選択をコピー
map("v", "<C-c>", "y", { noremap = true, silent = true, desc = "Copy" })

-- Backspace: 選択範囲を削除 (Delete と同じ挙動)
map("v", "<BS>", "d", { noremap = true, silent = true, desc = "Delete Selection" })

-- ============================================================
-- ファイル操作
-- ============================================================

-- Ctrl+S: 保存
map({ "n", "i", "v" }, "<C-s>", "<Cmd>w<CR>", { noremap = true, silent = true, desc = "Save file" })

-- Ctrl+W: タブ/バッファを閉じる (ウィンドウ操作は C-hjkl で代替)
-- 他のバッファに切り替えてから削除することで、ウィンドウごと閉じてnvimが終了するのを防ぐ
map("n", "<C-w>", function()
  local cur = vim.api.nvim_get_current_buf()
  local target
  local alt = vim.fn.bufnr("#")
  if alt > 0 and alt ~= cur and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
    target = alt
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= cur and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
        target = b
        break
      end
    end
  end
  if target then
    vim.api.nvim_win_set_buf(0, target)
  else
    vim.cmd("enew")
  end
  pcall(vim.api.nvim_buf_delete, cur, {})
end, { noremap = true, silent = true, desc = "Close buffer" })

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
-- インデント (Tab / Shift+Tab)
-- ============================================================

map("n", "<Tab>",   ">>", { noremap = true, desc = "Indent Line" })
map("n", "<S-Tab>", "<<", { noremap = true, desc = "Outdent Line" })
map("v", "<Tab>",   ">gv", { noremap = true, desc = "Indent" })
map("v", "<S-Tab>", "<gv", { noremap = true, desc = "Outdent" })

-- ============================================================
-- コマンドモード開始を > キーに変更 (デフォルトの : の代替)
-- ============================================================

map("n", ">", ":", { noremap = true, desc = "コマンドモード" })
map("n", "/", ":", { noremap = true, desc = "コマンドモード" })

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
-- Home / End
-- ============================================================

-- スマートHome: 最初の非空白文字 ↔ 行頭 (col 0) をトグル
local function smart_home()
  local col = vim.fn.col('.')
  local first_nonblank = vim.fn.match(vim.fn.getline('.'), '\\S') + 1
  if col ~= first_nonblank then
    vim.cmd('normal! ^')
  else
    vim.cmd('normal! 0')
  end
end

map("n", "<Home>", smart_home, { noremap = true, silent = true, desc = "Smart Home" })
map("n", "<End>",  "$",        { noremap = true, silent = true, desc = "End of Line" })

map("i", "<Home>", function()
  local col = vim.fn.col('.')
  local first_nonblank = vim.fn.match(vim.fn.getline('.'), '\\S') + 1
  return col ~= first_nonblank and '<C-o>^' or '<C-o>0'
end, { noremap = true, silent = true, expr = true, desc = "Smart Home" })
map("i", "<End>", "<End>", { noremap = true, silent = true, desc = "End of Line" })

map("v", "<Home>", "^", { noremap = true, silent = true, desc = "Smart Home" })
map("v", "<End>",  "$", { noremap = true, silent = true, desc = "End of Line" })

-- Shift+Home/End: 選択しながら移動
map("n", "<S-Home>", "v^", { noremap = true, silent = true, desc = "Select to Line Start" })
map("n", "<S-End>",  "v$", { noremap = true, silent = true, desc = "Select to Line End" })
map("v", "<S-Home>", "^",  { noremap = true, silent = true, desc = "Extend Selection to Line Start" })
map("v", "<S-End>",  "$h", { noremap = true, silent = true, desc = "Extend Selection to Line End" })
map("i", "<S-Home>", "<Esc>v^", { noremap = true, silent = true, desc = "Select to Line Start" })
map("i", "<S-End>",  "<Esc>v$", { noremap = true, silent = true, desc = "Select to Line End" })

-- ============================================================
-- Ctrl+矢印: 単語単位の移動
-- ============================================================

map("n", "<C-Right>", "w", { noremap = true, silent = true, desc = "Word Forward" })
map("n", "<C-Left>",  "b", { noremap = true, silent = true, desc = "Word Backward" })
map("i", "<C-Right>", "<C-o>w", { noremap = true, silent = true, desc = "Word Forward" })
map("i", "<C-Left>",  "<C-o>b", { noremap = true, silent = true, desc = "Word Backward" })
map("v", "<C-Right>", "w", { noremap = true, silent = true, desc = "Word Forward" })
map("v", "<C-Left>",  "b", { noremap = true, silent = true, desc = "Word Backward" })

-- Ghostty/zellij経由のCtrl+Shift+矢印 (CSI 1;10 D/C) を <C-S-Left/Right> に変換
-- nvimは CSI 1;5 (Ctrl+矢印) は認識するが CSI 1;10 (Ctrl+Shift+矢印) は認識しないため
for _, mode in ipairs({ "n", "i", "v", "x", "s" }) do
  vim.keymap.set(mode, "<Esc>[1;10D", "<C-S-Left>",  { remap = true, silent = true })
  vim.keymap.set(mode, "<Esc>[1;10C", "<C-S-Right>", { remap = true, silent = true })
end

-- Ctrl+Shift+矢印: 選択しながら単語単位の移動
map("n", "<C-S-Right>", "vw", { noremap = true, silent = true, desc = "Select Word Forward" })
map("n", "<C-S-Left>",  "vb", { noremap = true, silent = true, desc = "Select Word Backward" })
map("v", "<C-S-Right>", "w",  { noremap = true, silent = true, desc = "Extend Selection Word Forward" })
map("v", "<C-S-Left>",  "b",  { noremap = true, silent = true, desc = "Extend Selection Word Backward" })
map("i", "<C-S-Right>", "<Esc>vw", { noremap = true, silent = true, desc = "Select Word Forward" })
map("i", "<C-S-Left>",  "<Esc>vb", { noremap = true, silent = true, desc = "Select Word Backward" })

-- ============================================================
-- 上下矢印キーの端折り返し
-- 先頭行で↑ → ファイル先頭へ、最終行で↓ → ファイル末尾へ
-- ============================================================

local function up_or_gg()
  if vim.fn.line('.') == 1 then
    vim.cmd('normal! gg0')
  else
    vim.cmd('normal! k')
  end
end

local function down_or_G()
  if vim.fn.line('.') == vim.fn.line('$') then
    vim.cmd('normal! G$')
  else
    vim.cmd('normal! j')
  end
end

map("n", "<Up>",   up_or_gg,  { noremap = true, silent = true, desc = "Up / Go to File Start" })
map("n", "<Down>", down_or_G, { noremap = true, silent = true, desc = "Down / Go to File End" })

map("i", "<Up>", function()
  if vim.fn.line('.') == 1 then
    return '<C-o>gg<C-o>0'
  else
    return '<Up>'
  end
end, { noremap = true, silent = true, expr = true, desc = "Up / Go to File Start" })

map("i", "<Down>", function()
  if vim.fn.line('.') == vim.fn.line('$') then
    return '<C-o>G<C-o>$'
  else
    return '<Down>'
  end
end, { noremap = true, silent = true, expr = true, desc = "Down / Go to File End" })

-- Shift+上下矢印キーの端折り返し (選択しながら)
map("n", "<S-Up>", function()
  if vim.fn.line('.') == 1 then
    return 'vgg0'
  end
  return 'vk'
end, { noremap = true, silent = true, expr = true, desc = "Select Up / to File Start" })

map("n", "<S-Down>", function()
  if vim.fn.line('.') == vim.fn.line('$') then
    return 'vG$'
  end
  return 'vj'
end, { noremap = true, silent = true, expr = true, desc = "Select Down / to File End" })

map("x", "<S-Up>", function()
  if vim.fn.line('.') == 1 then
    return 'gg0'
  end
  return 'k'
end, { noremap = true, silent = true, expr = true, desc = "Extend Selection Up / to File Start" })

map("x", "<S-Down>", function()
  if vim.fn.line('.') == vim.fn.line('$') then
    return 'G$'
  end
  return 'j'
end, { noremap = true, silent = true, expr = true, desc = "Extend Selection Down / to File End" })

map("i", "<S-Up>", function()
  if vim.fn.line('.') == 1 then
    return '<Esc>vgg0'
  end
  return '<Esc>vk'
end, { noremap = true, silent = true, expr = true, desc = "Select Up / to File Start" })

map("i", "<S-Down>", function()
  if vim.fn.line('.') == vim.fn.line('$') then
    return '<Esc>vG$'
  end
  return '<Esc>vj'
end, { noremap = true, silent = true, expr = true, desc = "Select Down / to File End" })

-- ============================================================
-- 検索ハイライトのクリア
-- ============================================================

map("n", "<Esc>", "<Cmd>nohlsearch<CR>", o)
