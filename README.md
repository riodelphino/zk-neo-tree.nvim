# zk-neo-tree.nvim

An extention for [zk-nvim](https://github.com/zk-org/zk-nvim) that add ZK source to [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim).

Forked from [zk-org/neo-tree-zk.nvim](https://github.com/zk-org/neo-tree-zk.nvim). (unmaintained since 2022)


## Installation

Via [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "riodelphino/zk-neo-tree.nvim",
  requires = {
    "zk-org/zk-nvim"
    "nvim-neo-tree/neo-tree.nvim",
  },
}
```
Via [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "riodelphino/zk-neo-tree.nvim",
  requires = {
    "zk-org/zk-nvim"
    "nvim-neo-tree/neo-tree.nvim",
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
  bind_to_cwd = true, -- Follow cwd changes
  enable_git_status = true, -- Show git status markers and highlights
  filtered_items = {
    always_show = { -- remains visible even if other settings would normally hide it
      --".gitignored",
    },
    always_show_by_pattern = { -- uses glob style patterns
      --".env*",
    },
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
    never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
      --".DS_Store",
      --"thumbs.db"
    },
    never_show_by_pattern = { -- uses glob style patterns
      --".null-ls_*",
    },
    visible = false, -- when true, they will just be displayed differently than normal items
  },
  window = {
    mappings = {
      -- zk source
      ["z"] = "change_query",

      -- filesystem commands are also available
      -- (e.g. ["H"] = "toggle_hidden", )
    },
  },
  extra = {
    -- Scan also none-zk files and directories (e.g. ".zk/", dotfiles, empty directories, "*.jpg", e.t.c.)
    scan_none_zk_items = true,

    -- The fields fetched by `zk.api.list`
    select = { "absPath", "title"},

    ---Default name formatter
    ---@param notes table cached notes by zk.api.list
    ---@param node neotree.collections.ListNode
    name_formatter = function(note, node)
      return note and note.title or node.name or nil
    end,

    ---Additional customizer for text and highlight table
    ---@param rendere_nodes neotree.Render.Node[]
    ---@param note table? single cached note by zk.api.list
    ---@param node neotree.collections.ListNode
    name_extra_renderer = function(rendere_nodes, note, node)
      -- `rendere_nodes` arg is a table like:
      -- `{ { text = "<title_or_filename>", highlight = "<highlight_name>", } }`

      -- Sample code for adding filename only for zk file
      -- if note and note.title then
      --   table.insert(rendere_nodes, { text = node.name, highlight = "NeotreeDimText"})
      -- end
      return rendere_nodes
    end,

    ---Default sort function
    ---@param notes table cached notes by zk.api.list
    ---@param a table
    ---@param b table
    sorter = function(notes, a, b)
      -- 1. Sort by directories -> files
      if a.type ~= b.type then
        return a.type == "directory"
      end

      -- 2. Sort by none-hidden -> hidden
      local a_hidden = string.sub(a.name, 1, 1) == "."
      local b_hidden = string.sub(b.name, 1, 1) == "."
      if a_hidden ~= b_hidden then
        return not a_hidden
      end

      -- 3. Sort by titled files -> untitled files
      local a_title = notes[a.path] and notes[a.path].title
      local b_title = notes[b.path] and notes[b.path].title
      local a_has_title = a_title and a_title ~= ""
      local b_has_title = b_title and b_title ~= ""
      if a_has_title ~= b_has_title then
        return a_has_title
      end

      -- Sort by title
      if a_has_title and b_has_title then
        return a_title:lower() < b_title:lower()
      end

      -- Sort by name
      return a.name:lower() < b.name:lower()
    end,
  },
}
```

## Usage

From you zk directory, call `:Neotree source=zk` or `:Neotree zk`.

Then use the 'change_query' command (`z`) to see notes belonging to the selected query.


## Issues

- [ ] The sort by ZK note title is incorrect at first load. (-> it's correct when reopened.)
- [ ] `z` key waits for `zz`. (-> Disable `zz` keymap.)


## Related

- [zk-org/zk](https://github.com/zk-org/zk)
- [zk-org/zk-nvim](https://github.com/zk-org/zk-nvim)
- [nvim-neo-tree/neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim)
- [zk-org/neo-tree-zk.nvim](https://github.com/zk-org/neo-tree-zk.nvim) (unmaintained since 2022)
- [riodelphino/zk-snacks-explorer.nvim](https://github.com/riodelphino/zk-snacks-explorer.nvim)

