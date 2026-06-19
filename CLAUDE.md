# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`bookmark.nvim` is a Neovim plugin (Lua, no build step) that lets users bookmark files, lines, and exact cursor locations independently of Neovim's native `:mark` system. Bookmarks are stored as JSON and line/location bookmarks are live-tracked with extmarks so they follow edits.

Requires Neovim 0.10+.

## Module architecture

The plugin has four modules with a strict layering:

```
plugin/bookmarks.lua   ← user commands (thin wrappers, loads last)
lua/bookmarks/init.lua ← public API: setup(), bookmark_*, toggle_*, list(), get(), delete(), clear(), jump(), open(), close(), save(), load()
lua/bookmarks/ui.lua   ← floating popup: tabs (All/Files/Lines/Locations), keymaps, rendering via extmarks
lua/bookmarks/store.lua← data layer: in-memory M.bookmarks[], extmark management, JSON persistence
lua/bookmarks/config.lua← defaults + vim.tbl_deep_extend merge; M.options is the live config table
```

**Data flow:** `init.lua` calls `store` and `ui`; `ui.lua` calls `store` directly for reads/deletes. `store` and `ui` both read `config.options`. `plugin/bookmarks.lua` calls `require("bookmarks")` lazily via a local `api()` helper (avoids eager loading at Neovim startup).

## Key design details

**Extmarks:** `store.lua` maintains a dedicated namespace (`bookmarks_nvim`). Each line/location bookmark gets a live extmark when its buffer is open (`set_extmark`). Positions are synced back from extmarks via `sync_from_extmark` / `sync_all` before any list/save/jump operation. The `_extmark = { buf, id }` field is runtime-only and never written to JSON.

**Auto-setup:** `init.lua` has `ensure_setup()` so calling any API function before `setup()` self-initializes with defaults. Autocmds (`BufReadPost`, `BufEnter`, `BufWritePost`, `ColorScheme`, `VimLeavePre`) are registered only once via `M._setup_done`.

**ID generation:** `store.gen_id()` produces `"<os.time()>_<counter>"` strings — stable and sortable.

**Popup state:** `ui.lua` holds a module-level `state` table (`buf`, `win`, `filter`, `map`, `entry_lines`). `map` is a 1-based lnum→bookmark table rebuilt on every `render()` call.

**Commands:** `plugin/bookmarks.lua` accepts plural/singular kind names (`files`/`file`, `lines`/`line`, `locations`/`location`) and normalizes via a `KIND` table.

## Development workflow

No build step. To test changes, load the plugin in a Neovim session:

```lua
-- In Neovim, source the plugin directly:
:luafile lua/bookmarks/init.lua   -- reload a specific module
:lua package.loaded["bookmarks"] = nil; require("bookmarks").setup()  -- full reload
```

To add a new config option: add the default in `config.lua` under `M.defaults`, then read it from `config.options` wherever needed.

To add a new public API function: add it to `init.lua` with an `ensure_setup()` call at the top.
