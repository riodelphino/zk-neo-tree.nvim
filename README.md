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

zk-specific config:
```lua
{
  follow_current_file = {
    enabled = true,
  },
  before_render = false, -- function(state) end,
  enable_git_status = true,
  bind_to_cwd = true,
  use_libuv_file_watcher = true,
  filtered_items = {
    visible = false, -- when true, they will just be displayed differently than normal items
    hide_dotfiles = true,
    hide_gitignored = true,
    hide_hidden = true, -- only works on Windows for hidden files/directories
    hide_by_name = {
      --"node_modules"
    },
    hide_by_pattern = { -- uses glob style patterns
      --"*.meta",
      --"*/src/*/tsconfig.json",
    },
    always_show = { -- remains visible even if other settings would normally hide it
      --".gitignored",
    },
    always_show_by_pattern = { -- uses glob style patterns
      --".env*",
    },
    never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
      --".DS_Store",
      --"thumbs.db"
    },
    never_show_by_pattern = { -- uses glob style patterns
      --".null-ls_*",
    },
  },
  window = {
    mappings = {
      -- zk source
      ["n"] = "change_query",
      -- filesystem source TODO: Check if all filesystem commands are available.
      ["H"] = "toggle_hidden",
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
      ["f"] = "filter_on_submit",
      ["<c-x>"] = "clear_filter",
      ["[g"] = "prev_git_modified",
      ["]g"] = "next_git_modified",
    },
  },
}
```

## Usage

From you zk directory, call `:Neotree source=zk` or `:Neotree zk`.

Then use the 'change_query' command (`n`) to see notes belonging to the selected query.
