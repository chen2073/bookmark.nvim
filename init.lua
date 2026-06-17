-- bookmarks.nvim :: public API & setup.
--
-- Bookmark files, lines and cursor locations with your own persistent store
-- (independent of Neovim's native marks / location list), browse them in a
-- popup, and drive everything from Lua.

local config = require("bookmarks.config")
local store = require("bookmarks.store")
local ui = require("bookmarks.ui")

local M = {}

M._setup_done = false

----------------------------------------------------------------------
-- internal
----------------------------------------------------------------------

local function notify(msg, level)
  vim.notify("[bookmarks] " .. msg, level or vim.log.levels.INFO)
end

local function ensure_setup()
  if not M._setup_done then
    M.setup()
  end
end

local function current_path()
  return vim.api.nvim_buf_get_name(0)
end

local function require_named_buffer()
  local path = current_path()
  if path == "" then
    notify("current buffer has no file name", vim.log.levels.WARN)
    return nil
  end
  return path
end

local function set_default_highlights()
  local function def(name, val)
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, val))
  end
  def("BookmarksSign", { link = "DiagnosticSignInfo" })
  def("BookmarksLocSign", { link = "DiagnosticSignHint" })
  def("BookmarksUITab", { link = "Comment" })
  def("BookmarksUITabActive", { link = "Title", bold = true })
  def("BookmarksUITagFile", { link = "Directory" })
  def("BookmarksUITagLine", { link = "Function" })
  def("BookmarksUITagLocation", { link = "Identifier" })
  def("BookmarksUIPos", { link = "Number" })
  def("BookmarksUIName", { link = "Normal" })
  def("BookmarksUIPath", { link = "Comment" })
  def("BookmarksUILabel", { link = "String" })
  def("BookmarksUISep", { link = "FloatBorder" })
  def("BookmarksUIHint", { link = "Comment" })
end

----------------------------------------------------------------------
-- setup
----------------------------------------------------------------------

function M.setup(opts)
  config.setup(opts)
  set_default_highlights()

  if M._setup_done then
    return M
  end
  M._setup_done = true

  local group = vim.api.nvim_create_augroup("BookmarksNvim", { clear = true })

  -- Attach extmarks as buffers are opened/entered so line/location bookmarks
  -- track edits live.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
    group = group,
    callback = function(args)
      store.attach_buffer(args.buf)
    end,
  })

  -- Persist updated positions after a buffer is written.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function()
      store.sync_all()
      if config.options.auto_save then
        store.save()
      end
    end,
  })

  -- Re-apply theme links after a colorscheme change.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = set_default_highlights,
  })

  -- Final save on exit.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      store.save()
    end,
  })

  if config.options.auto_load then
    store.load()
  end

  return M
end

----------------------------------------------------------------------
-- creating bookmarks
----------------------------------------------------------------------

local function report(bm, status)
  if not bm then
    return nil
  end
  if status == "exists" then
    notify("already bookmarked", vim.log.levels.WARN)
  end
  return bm
end

--- Bookmark a file (defaults to the current buffer).
function M.bookmark_file(path, label)
  ensure_setup()
  path = path or current_path()
  if not path or path == "" then
    notify("current buffer has no file name", vim.log.levels.WARN)
    return nil
  end
  local bm, status = store.add({ type = "file", path = path, label = label })
  return report(bm, status)
end

--- Bookmark the current line of the current buffer.
function M.bookmark_line(label)
  ensure_setup()
  local path = require_named_buffer()
  if not path then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local bm, status = store.add({ type = "line", path = path, line = line, label = label })
  return report(bm, status)
end

--- Bookmark the exact cursor location (line + column) of the current buffer.
function M.bookmark_location(label)
  ensure_setup()
  local path = require_named_buffer()
  if not path then
    return nil
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local bm, status = store.add({
    type = "location",
    path = path,
    line = cur[1],
    col = cur[2] + 1,
    label = label,
  })
  return report(bm, status)
end

--- Toggle a line bookmark on the current line (add if absent, remove if present).
function M.toggle_line()
  ensure_setup()
  local path = require_named_buffer()
  if not path then
    return nil
  end
  path = store.normalize(path)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, bm in ipairs(store.bookmarks) do
    if bm.type == "line" and bm.path == path then
      store.sync_from_extmark(bm)
      if bm.line == line then
        store.delete(bm.id)
        notify("line bookmark removed")
        return nil
      end
    end
  end
  return M.bookmark_line()
end

--- Toggle a file bookmark for the current buffer.
function M.toggle_file()
  ensure_setup()
  local path = require_named_buffer()
  if not path then
    return nil
  end
  path = store.normalize(path)
  for _, bm in ipairs(store.bookmarks) do
    if bm.type == "file" and bm.path == path then
      store.delete(bm.id)
      notify("file bookmark removed")
      return nil
    end
  end
  return M.bookmark_file()
end

----------------------------------------------------------------------
-- reading / removing
----------------------------------------------------------------------

--- Return a position-synced array of bookmarks. `kind` may be
--- nil/"all"/"file"/"line"/"location".
function M.list(kind)
  ensure_setup()
  return store.list(kind)
end

--- Get a single bookmark by id.
function M.get(id)
  ensure_setup()
  return store.get(id)
end

--- Delete one bookmark by id. Returns true if something was removed.
function M.delete(id)
  ensure_setup()
  return store.delete(id)
end

--- Clear all bookmarks, or only those of `kind` ("file"/"line"/"location").
--- Returns the number removed.
function M.clear(kind)
  ensure_setup()
  if kind == "all" then
    kind = nil
  end
  return store.delete_all(kind)
end

----------------------------------------------------------------------
-- navigation
----------------------------------------------------------------------

--- Jump to a bookmark by id. Opens the file and (for line/location) moves the
--- cursor. Returns true on success.
function M.jump(id)
  ensure_setup()
  local bm = store.get(id)
  if not bm then
    notify("no such bookmark: " .. tostring(id), vim.log.levels.WARN)
    return false
  end
  store.sync_from_extmark(bm)

  vim.cmd("edit " .. vim.fn.fnameescape(bm.path))

  if bm.type ~= "file" and bm.line then
    local line = bm.line
    local count = vim.api.nvim_buf_line_count(0)
    if line > count then
      line = count
    end
    if line < 1 then
      line = 1
    end
    local col = (bm.type == "location" and bm.col) and (bm.col - 1) or 0
    pcall(vim.api.nvim_win_set_cursor, 0, { line, math.max(0, col) })
    pcall(vim.cmd, "normal! zz")
  end
  return true
end

----------------------------------------------------------------------
-- popup
----------------------------------------------------------------------

--- Open the popup menu. `kind` selects the initial tab
--- ("all"/"file"/"line"/"location").
function M.open(kind)
  ensure_setup()
  ui.open(kind)
end

--- Close the popup if open.
function M.close()
  ui.close()
end

----------------------------------------------------------------------
-- persistence passthrough
----------------------------------------------------------------------

function M.save()
  ensure_setup()
  return store.save()
end

function M.load()
  ensure_setup()
  store.load()
end

return M
