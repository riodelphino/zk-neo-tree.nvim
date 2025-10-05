# Neo-tree-zk

A [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) source for [zk-nvim](https://github.com/mickael-menu/zk-nvim).

## Installation

Via [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "zk-org/neo-tree-zk.nvim",
  requires = {
    "nvim-neo-tree/neo-tree.nvim",
    "zk-org/zk-nvim"
  },
}
```
Via [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "zk-org/neo-tree-zk.nvim",
  requires = {
    "nvim-neo-tree/neo-tree.nvim",
    "zk-org/zk-nvim"
  },
}
```

## Setup

In your [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) config:

```lua
require("neo-tree").setup({
  sources = {
    -- default sources
    "filesystem",
    "buffers",
    "git_status",
    -- user sources goes here
    "zk",
  },
  zk = {
    -- Leave this as an empty table,
    -- Or add your customized zk-specific config here.
  }
})
```

## Defaults

> [!warning]
> Some filtering features in `filtered_items` are not available.
> (Because hidden files like `.zk` are not listed by `zk.api.list`)

zk-specific config:
```lua
-- FIX: Should remove unavailable config and above warning.
{
  follow_current_file = {
    enabled = true,
  },
  before_render = false, -- function(state) end,
  bind_to_cwd = true, -- Follow cwd changes
  enable_git_status = true, -- Show git status markers and highlights
  enable_diagnostics = true, -- Catch the lsp diagnostic updates
  enable_opened_markers = true, -- Show opened markers
  enable_modified_markers = true, -- Show modified markers
  git_status_async = true,
  use_libuv_file_watcher = true,
  filtered_items = {
    always_show = { -- NOT WORKS / remains visible even if other settings would normally hide it
      --".gitignored",
    },
    always_show_by_pattern = { -- NOT WORKS / uses glob style patterns
      --".env*",
    },
    hide_dotfiles = true, -- NOT WORKS
    hide_gitignored = true, -- NOT WORKS
    hide_hidden = true, -- NOT WORKS / only works on Windows for hidden files/directories
    hide_by_name = {
      --"node_modules"
    },
    hide_by_pattern = { -- uses glob style patterns
      --"*.meta",
      --"*/src/*/tsconfig.json",
    },
    never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
      --".DS_Store",
      --"thumbs.db"
    },
    never_show_by_pattern = { -- uses glob style patterns
      --".null-ls_*",
    },
    visible = false, -- NOT WORKS / when true, they will just be displayed differently than normal items
  },
  window = {
    mappings = {
      -- zk source
      ["n"] = "change_query",

      -- filesystem commands are also available
      -- (e.g. ["H"] = "toggle_hidden", )
    },
  },
}
```

## Usage

From you zk directory, call `:Neotree source=zk` or `:Neotree zk`.

Then use the 'change_query' command (`n`) to see notes belonging to the selected query.
