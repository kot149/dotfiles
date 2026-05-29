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

-- nvim外でのファイル変更・git操作を自動検出
opt.autoread = true
local auto_reload = vim.api.nvim_create_augroup("AutoReload", { clear = true })
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  group = auto_reload,
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

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
-- selection=exclusive: 選択範囲の末尾の文字を含めない (VSCode 風)
-- これがないと Shift+Right 1回で 2文字選択され、削除時に 1文字余分に消える
opt.selection = "exclusive"

-- カーソル: ブロックを避けつつ Normal モードでの縦棒の位置ズレも回避
-- Normal/Visual/Command: 下線 (hor20)、Insert/Replace: 縦棒 (ver25)、点滅なし
opt.guicursor = "n-v-c-sm:hor20-blinkon0,i-ci-ve:ver25-blinkon0,r-cr-o:hor20-blinkon0"

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

-- neo-tree などの特殊バッファに入ったら強制的に Normal モードへ戻す
-- (別経路で Insert のままウィンドウ移動した場合でも E21 を防ぐ)
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = insert_on_enter,
  callback = function(args)
    if skip_filetypes[vim.bo[args.buf].filetype] then
      if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
        vim.cmd("stopinsert")
      end
    end
  end,
})
