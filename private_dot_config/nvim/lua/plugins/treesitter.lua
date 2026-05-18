return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    main = "nvim-treesitter.configs",
    opts = {
      ensure_installed = {
        "lua", "vim", "vimdoc", "nix",
        "javascript", "typescript", "tsx", "html", "css", "json",
        "python", "go", "rust",
        "bash", "yaml", "toml", "markdown", "markdown_inline",
      },
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },
}
