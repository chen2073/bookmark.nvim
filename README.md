# bookmarks.nvim

Bookmark **files**, **lines**, and exact cursor **locations** in Neovim, browse
them in a popup, and drive everything from a Lua API.

Bookmarks live in their own JSON store and are **independent of Neovim's native
`:mark`s and location list**. Line and location bookmarks are tracked with
extmarks, so they follow edits while a buffer is open, and survive restarts.

Requires Neovim 0.10+ (uses extmark signs and floating-window titles).

## Features

- Three bookmark kinds: `file`, `line` (file + line), `location` (file + line + column).
- A floating popup with tabs for **All / Files / Lines / Locations**, showing counts.
- Delete a single bookmark or clear everything (or just the current tab) from the popup.
- Jump straight to a bookmark from the popup.
- Sign-column markers for line/location bookmarks that move with your edits.
- Persistent across sessions (JSON file under `stdpath("data")`).
- Full Lua API mirroring every feature.

## Install

Using **lazy.nvim**:

```lua
{
  dir = "/path/to/bookmarks.nvim", -- or a git URL once published
  config = function()
    require("bookmarks").setup()
  end,
}
```

Using **packer.nvim**:

```lua
use({
  "/path/to/bookmarks.nvim",
  config = function()
    require("bookmarks").setup()
  end,
})
```

Calling `setup()` is optional — the plugin self-initializes with defaults on
first use — but it is the place to pass options and is recommended.

## Configuration

These are the defaults; pass any subset to `setup()`:

```lua
require("bookmarks").setup({
  storage_path = vim.fn.stdpath("data") .. "/bookmarks.json",
  auto_save = true,
  auto_load = true,

  signs = {
    enable = true,
    line = { text = "▸", texthl = "BookmarksSign" },
    location = { text = "◆", texthl = "BookmarksLocSign" },
  },

  ui = {
    width = 0.6,        -- fraction of columns, or an integer for absolute width
    height = 0.6,       -- fraction of lines,   or an integer for absolute height
    border = "rounded",
    title = " Bookmarks ",
  },

  -- Keymaps active only inside the popup:
  keymaps = {
    jump = "<CR>",
    delete = "d",
    delete_all = "D",
    next_tab = "<Tab>",
    prev_tab = "<S-Tab>",
    close = { "q", "<Esc>" },
    filter_all = "0",
    filter_files = "1",
    filter_lines = "2",
    filter_locations = "3",
  },
})
```

### Suggested global keymaps

The plugin defines no global keymaps. Add your own, for example:

```lua
local bm = require("bookmarks")
vim.keymap.set("n", "<leader>bf", bm.bookmark_file,     { desc = "Bookmark file" })
vim.keymap.set("n", "<leader>bl", bm.toggle_line,       { desc = "Toggle line bookmark" })
vim.keymap.set("n", "<leader>bk", bm.bookmark_location, { desc = "Bookmark location" })
vim.keymap.set("n", "<leader>bb", function() bm.open() end, { desc = "Open bookmarks" })
```

## Commands

| Command | Description |
| --- | --- |
| `:BookmarkFile [label]` | Bookmark the current file. |
| `:BookmarkLine [label]` | Bookmark the current line. |
| `:BookmarkLocation [label]` | Bookmark the cursor's line + column. |
| `:BookmarkToggleLine` | Toggle a line bookmark on the current line. |
| `:BookmarkToggleFile` | Toggle a file bookmark for the current buffer. |
| `:Bookmarks [all\|files\|lines\|locations]` | Open the popup (optionally on a tab). |
| `:BookmarksClear [all\|files\|lines\|locations]` | Clear bookmarks (all by default). |

## Inside the popup

| Key | Action |
| --- | --- |
| `<CR>` | Jump to the bookmark under the cursor. |
| `d` | Delete the bookmark under the cursor. |
| `D` | Clear all bookmarks in the current tab (asks for confirmation). |
| `<Tab>` / `<S-Tab>` | Next / previous tab. |
| `0` / `1` / `2` / `3` | Jump to All / Files / Lines / Locations. |
| `q` / `<Esc>` | Close. |

## Lua API

```lua
local bm = require("bookmarks")

bm.setup(opts)            -- configure (optional)

-- create
bm.bookmark_file(path?, label?)   -- path defaults to current buffer
bm.bookmark_line(label?)          -- current line
bm.bookmark_location(label?)      -- current cursor line + column
bm.toggle_line()                  -- add/remove a line bookmark here
bm.toggle_file()                  -- add/remove a file bookmark for this buffer

-- read / remove
bm.list(kind?)            -- kind = nil|"all"|"file"|"line"|"location" -> array
bm.get(id)                -- single bookmark table, or nil
bm.delete(id)             -- delete one; returns true if removed
bm.clear(kind?)           -- delete all, or only one kind; returns count

-- navigate / UI
bm.jump(id)               -- open file and move cursor; returns true on success
bm.open(kind?)            -- open the popup on a given tab
bm.close()                -- close the popup

-- persistence (also happens automatically)
bm.save()
bm.load()
```

### Bookmark record shape

`list()` / `get()` return tables like:

```lua
{
  id = "1718600000_3",     -- stable unique id
  type = "location",        -- "file" | "line" | "location"
  path = "/abs/path/file.lua",
  line = 42,                -- present for line/location (current, edit-tracked)
  col = 7,                  -- present for location (1-based)
  label = "todo",           -- optional
  created_at = 1718600000,  -- os.time()
}
```

### Example

```lua
local bm = require("bookmarks")

local b = bm.bookmark_location("review here")
-- ... later ...
bm.jump(b.id)

for _, item in ipairs(bm.list("line")) do
  print(item.path, item.line, item.label)
end

bm.clear("location") -- drop all location bookmarks
```

## How positions stay accurate

When a buffer is open, each line/location bookmark is backed by an extmark, so
inserting or deleting lines above it shifts the bookmark with the content. The
stored line/column are refreshed from the extmark whenever you save the buffer,
list bookmarks, jump, or exit Neovim. When the file isn't open, the last known
position is used.

## Highlight groups

All link to sensible defaults and can be overridden:

`BookmarksSign`, `BookmarksLocSign`, `BookmarksUITab`, `BookmarksUITabActive`,
`BookmarksUITagFile`, `BookmarksUITagLine`, `BookmarksUITagLocation`,
`BookmarksUIPos`, `BookmarksUIName`, `BookmarksUIPath`, `BookmarksUILabel`,
`BookmarksUISep`, `BookmarksUIHint`.
