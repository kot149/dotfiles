return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function()
          return vim.fn.executable("make") == 1
        end,
      },
    },
    cmd = "Telescope",
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")

      telescope.setup({
        defaults = {
          -- Emacs isearch 風のキーバインド
          mappings = {
            i = {
              ["<C-n>"] = actions.move_selection_next,
              ["<C-p>"] = actions.move_selection_previous,
              ["<C-g>"] = actions.close,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-x>2"] = actions.select_horizontal,
              ["<C-x>3"] = actions.select_vertical,
            },
            n = {
              ["<C-g>"] = actions.close,
              ["q"] = actions.close,
            },
          },
          layout_config = { prompt_position = "top" },
          sorting_strategy = "ascending",
          border = true,
          borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
        },
      })

      pcall(telescope.load_extension, "fzf")
    end,
  },
}
