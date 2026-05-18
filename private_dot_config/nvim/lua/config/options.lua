local opt = vim.opt

opt.number = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.cursorline = true
opt.showmode = false
opt.wrap = false
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
opt.clipboard = "unnamedplus"

opt.undofile = true
opt.swapfile = false
opt.backup = false

-- C-x<C-s> などのシーケンスが快適に入力できるタイムアウト
opt.timeoutlen = 500

opt.completeopt = "menu,menuone,noselect"

opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99
