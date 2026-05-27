return {
  -- ステータスライン
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
        component_separators = "|",
        section_separators = "",
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  -- アイコン
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- キーバインドヒント (Emacs which-key.el 相当)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 500,
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)
      wk.add({
        { "<leader>g", group = "Git" },
        { "<leader>.",  desc = "Code Action" },
        { "<leader>f",  desc = "Find in workspace" },
        { "<leader>p",  desc = "Command Palette" },
        { "<leader>s",  desc = "Flash Jump" },
        { "<leader>w",  group = "Window" },
      })
    end,
  },

  -- インデントガイド
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      indent = { char = "│" },
      scope = { enabled = false },
    },
  },

  -- Bufferline (Emacs のタブバー相当)
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        show_buffer_close_icons = false,
        show_close_icon = false,
      },
    },
  },

  -- 通知
  {
    "rcarriga/nvim-notify",
    opts = { timeout = 3000, render = "compact" },
    config = function(_, opts)
      require("notify").setup(opts)
      vim.notify = require("notify")
    end,
  },
}
