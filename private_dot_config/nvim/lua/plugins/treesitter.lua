return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install({
        "lua", "vim", "vimdoc", "nix",
        "javascript", "typescript", "tsx", "html", "css", "json",
        "python", "go", "rust",
        "bash", "yaml", "toml", "markdown", "markdown_inline",
      })
    end,
  },
}
