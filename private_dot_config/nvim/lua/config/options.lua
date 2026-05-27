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

-- Shift+矢印キーでテキスト選択 (ノーマル・挿入モード両対応)
-- startsel: Shift+矢印でビジュアル選択開始
-- stopsel:  Shiftなし矢印で選択解除
opt.keymodel = "startsel,stopsel"

opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99
