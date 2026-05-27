local opt = vim.opt

opt.number = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.cursorline = true
opt.showmode = false
opt.wrap = true
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true

opt.splitright = true
opt.splitbelow = true

opt.scrolloff = 8
opt.sidescrolloff = 8

opt.mouse = "a"
opt.whichwrap:append("<,>,[,]") -- 行末→次行先頭、行頭→前行末 (通常・挿入モード)
opt.clipboard = "unnamedplus"

opt.undofile = true
opt.swapfile = false
opt.backup = false

-- C-x<C-s> などのシーケンスが快適に入力できるタイムアウト
opt.timeoutlen = 500

opt.completeopt = "menu,menuone,noselect"

-- Shift+矢印キーでテキスト選択 (VSCode風)
-- startsel: Shift+矢印で選択開始
-- stopsel:  Shiftなし矢印で選択解除
-- selectmode=key: Shift起動の選択は Visual ではなく Select モードに入る
--                  (Select モードでは印字キー入力で選択が置換されInsertに戻る)
opt.keymodel = "startsel,stopsel"
opt.selectmode = "key"

opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99

-- VSCode 風: ファイルバッファに入ったら自動で Insert モードに入る
-- (Neo-tree / Telescope / ターミナル / quickfix などの特殊バッファは除外)
local insert_on_enter = vim.api.nvim_create_augroup("InsertOnBufEnter", { clear = true })
local skip_filetypes = {
  ["neo-tree"] = true,
  ["TelescopePrompt"] = true,
  ["lazy"] = true,
  ["mason"] = true,
  ["help"] = true,
  ["qf"] = true,
  ["gitcommit"] = true,
  ["checkhealth"] = true,
  [""] = false, -- 通常ファイルは空文字列のことがあるので false で素通し
}
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = insert_on_enter,
  callback = function(args)
    local buf = args.buf
    if vim.bo[buf].buftype ~= "" then return end
    if not vim.bo[buf].modifiable then return end
    if skip_filetypes[vim.bo[buf].filetype] then return end
    -- 既に Insert/Terminal モードなら何もしない
    local mode = vim.api.nvim_get_mode().mode
    if mode:sub(1, 1) == "i" or mode:sub(1, 1) == "t" then return end
    vim.cmd("startinsert")
  end,
})
