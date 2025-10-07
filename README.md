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
-- FIX: Should remove unavailable config and above warning. or, merge with filesystem items (difficult)
{
  follow_current_file = {
    enabled = true,
  },
  before_render = false, -- function(state) end,
  bind_to_cwd = true, -- Follow cwd changes
  enable_git_status = true, -- Show git status markers and highlights
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
  extra = {
    -- Scan also none-zk files and directories (e.g. ".zk/", dotfiles, empty directories, "*.jpg", e.t.c.)
    scan_none_zk_items = true, -- FIX: Should be here or root?

    -- Merge filesystem source commands
    merge_filesystem_commands = true,

    -- The fields fetched by `zk.api.list`
    select = { "absPath", "title"},

    ---Default name formatter
    ---@param notes table cached notes by zk.api.list
    ---@param node neotree.collections.ListNode
    name_formatter = function(note, node)
      return note and note.title or node.name or nil
    end,

    ---Additional customizer for neotree.Render.Node table
    ---@param rendere_nodes neotree.Render.Node[]
    ---@param note table? single cached note by zk.api.list
    ---@param node neotree.collections.ListNode
    name_extra_renderer = function(rendere_nodes, note, node)
      -- The given `rendere_nodes` arg is a table: `{ { text = "<title_or_filename>", highlight = "<highlight_name>", } }`

      -- Sample code for adding filename only for zk file
      -- if note and note.title then
      --   table.insert(rendere_nodes, { text = node.name, highlight = "NeotreeDimText"})
      -- end
      return rendere_nodes
    end,

    ---Default sort function (directory > title > filename)
    ---@param notes table cached notes by zk.api.list
    ---@param a table
    ---@param b table
    sorter = function(notes, a, b)
      -- 1. Directories come first
      if a.type == "directory" and b.type ~= "directory" then
        return true
      elseif a.type ~= "directory" and b.type == "directory" then
        return false
      elseif a.type == "directory" and b.type == "directory" then
        return a.name:lower() < b.name:lower() -- Sort by directory name
      end
      -- Both are files
      local a_note = notes[a.path]
      local b_note = notes[b.path]
      local a_title = a_note and a_note.title
      local b_title = b_note and b_note.title
      -- 2. Titles come second
      if a_title and not b_title then
        return true
      elseif not a_title and b_title then
        return false
      elseif a_title and b_title then -- Sort by Title
        if a_title:lower() == b_title:lower() then
          return a.name:lower() < b.name:lower()
        end
        return a_title:lower() < b_title:lower()
      end
      -- 3. Both no title
      return a.name:lower() < b.name:lower() -- Sort by filename
    end,
  },
}
```

## Usage

From you zk directory, call `:Neotree source=zk` or `:Neotree zk`.

Then use the 'change_query' command (`n`) to see notes belonging to the selected query.
