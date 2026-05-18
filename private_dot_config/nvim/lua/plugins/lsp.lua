return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- mason: ニックスで管理していないLSPをインストールするUI
      require("mason").setup({ ui = { border = "rounded" } })

      -- nix 管理の LSP + mason 管理の LSP を統合
      require("mason-lspconfig").setup({
        ensure_installed = {
          "ts_ls", "eslint",
          "html", "cssls", "jsonls",
          "pyright",
          "gopls",
          "rust_analyzer",
          "bashls",
          "yamlls",
        },
        automatic_installation = false,
      })

      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- nix 管理: lua-language-server
      lspconfig.lua_ls.setup({
        capabilities = capabilities,
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      })

      -- nix 管理: nil (Nix LSP)
      lspconfig.nil_ls.setup({
        capabilities = capabilities,
        settings = {
          ["nil"] = {
            formatting = { command = { "nixpkgs-fmt" } },
          },
        },
      })

      -- mason 管理のサーバーを自動セットアップ
      require("mason-lspconfig").setup_handlers({
        function(server_name)
          lspconfig[server_name].setup({ capabilities = capabilities })
        end,
      })

      -- 診断表示の設定
      vim.diagnostic.config({
        virtual_text = { prefix = "●" },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded" },
      })
    end,
  },

  -- LSP 進捗表示
  {
    "j-hui/fidget.nvim",
    opts = { notification = { window = { winblend = 0 } } },
  },

  -- 診断リスト (VSCode Problems パネル相当)
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = { use_diagnostic_signs = true },
    keys = {
      -- Ctrl+Shift+M: Problems パネル (VSCode 風)
      { "<C-S-m>", "<Cmd>Trouble diagnostics toggle<CR>",              desc = "Problems Panel" },
      { "<leader>xx", "<Cmd>Trouble diagnostics toggle<CR>",           desc = "Diagnostics" },
      { "<leader>xb", "<Cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Buffer Diagnostics" },
    },
  },
}
