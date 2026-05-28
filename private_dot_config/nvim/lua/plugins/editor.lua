return {
  -- ファイルエクスプローラ (VSCode Explorer)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    cmd = "Neotree",
    init = function()
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          -- 引数なし起動 or ディレクトリ指定時のみ自動表示
          local argv = vim.fn.argv()
          if #argv == 0 or (argv[1] and vim.fn.isdirectory(argv[1]) == 1) then
            vim.schedule(function()
              require("neo-tree.command").execute({ action = "show" })
            end)
          end
        end,
      })
    end,
    opts = {
      close_if_last_window = true,
      window = {
        width = 30,
        mappings = {
          -- ダブルクリックでファイルを開く / ディレクトリをトグル
          ["<2-LeftMouse>"] = "open",
        },
      },
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
        },
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
      },
    },
  },

  -- Git サイン (VSCode GitLens 相当)
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add          = { text = "▎" },
        change       = { text = "▎" },
        delete       = { text = "▁" },
        topdelete    = { text = "▔" },
        changedelete = { text = "▎" },
      },
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        local function bmap(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, silent = true, desc = desc })
        end
        -- Alt+F3 / Shift+Alt+F3 でハンク移動 (VSCode 風)
        bmap("n", "<M-F3>",   gs.next_hunk,  "Next Hunk")
        bmap("n", "<M-S-F3>", gs.prev_hunk,  "Prev Hunk")
        -- leader から git 操作
        bmap("n", "<leader>gs", gs.stage_hunk,  "Stage Hunk")
        bmap("n", "<leader>gr", gs.reset_hunk,  "Reset Hunk")
        bmap("n", "<leader>gd", gs.diffthis,    "Diff This")
        bmap("n", "<leader>gb", gs.blame_line,  "Blame Line")
      end,
    },
  },

  -- コメントトグル (keymaps.lua の Ctrl+/ から呼ばれる)
  {
    "numToStr/Comment.nvim",
    lazy = true,
    opts = {},
  },

  -- 自動括弧補完
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = { check_ts = true },
  },

  -- サラウンド操作 (VSCode Surround 拡張相当)
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    opts = {},
  },

  -- フォーマッタ (VSCode Format Document 相当: Shift+Alt+F)
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua        = { "stylua" },
        nix        = { "nixpkgs_fmt" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        tsx        = { "prettier" },
        html       = { "prettier" },
        css        = { "prettier" },
        json       = { "prettier" },
        yaml       = { "prettier" },
        markdown   = { "prettier" },
        python     = { "ruff_format" },
        go         = { "gofmt" },
        rust       = { "rustfmt" },
      },
      format_on_save = { timeout_ms = 2000, lsp_fallback = true },
    },
    keys = {
      -- Shift+Alt+F: フォーマット (VSCode Shift+Alt+F)
      { "<M-S-f>", function() require("conform").format({ async = true, lsp_fallback = true }) end, desc = "Format Document" },
    },
  },

  -- ジャンプ (VSCode の Go to Symbol / Search 強化)
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "<leader>s", function() require("flash").jump() end, mode = { "n", "x", "o" }, desc = "Flash Jump" },
    },
  },

  -- UI 強化 (コマンドラインをフローティング表示)
  {
    "folke/noice.nvim",
    dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
    opts = {
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
        signature = { enabled = false },
      },
      presets = {
        bottom_search = true,
        command_palette = false,
        long_message_to_split = true,
      },
      -- コマンドパレット: 入力ボックスを上寄りに、候補リストをその直下に表示
      views = {
        cmdline_popup = {
          position = { row = "30%", col = "50%" },
          size = { min_width = 64, width = "auto", height = "auto" },
          border = { style = "rounded", padding = { 0, 1 } },
          win_options = {
            winhighlight = {
              Normal = "Normal",
              FloatBorder = "DiagnosticInfo",
            },
          },
        },
        popupmenu = {
          relative = "editor",
          position = { row = "30%", col = "50%" },
          size = { width = 64, height = 12 },
          border = { style = "rounded", padding = { 0, 1 } },
          win_options = {
            winhighlight = {
              Normal = "Normal",
              FloatBorder = "DiagnosticInfo",
            },
          },
        },
      },
    },
  },
}
