-- bookmarks.nvim :: storage, persistence and live-position tracking.
--
-- This module owns the bookmark data and does NOT use Neovim's native
-- `:mark` / location-list machinery. Line and location bookmarks are tracked
-- with extmarks (namespace below) so they follow edits while a buffer is open,
-- and are persisted as plain (path, line, col) records in a JSON file.

local config = require("bookmarks.config")

local M = {}

-- In-memory list of bookmark records.
--   { id, type = "file"|"line"|"location", path, line?, col?, label?, created_at }
-- Runtime-only field `_extmark = { buf, id }` is never persisted.
M.bookmarks = {}

-- Dedicated namespace for our extmarks / signs.
M.ns = vim.api.nvim_create_namespace("bookmarks_nvim")

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local id_counter = 0
local function gen_id()
  id_counter = id_counter + 1
  return string.format("%d_%d", os.time(), id_counter)
end

--- Resolve a path to a normalized absolute path. Returns nil for unnamed buffers.
function M.normalize(path)
  if path == nil or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

--- Find a loaded buffer whose name matches the given absolute path.
function M.get_buf_for_path(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and M.normalize(name) == path then
        return buf
      end
    end
  end
  return nil
end

----------------------------------------------------------------------
-- extmark management (the live-tracking layer)
----------------------------------------------------------------------

--- Place (or refresh) an extmark for a line/location bookmark in a buffer.
-- No-op for file bookmarks and for paths with no loaded buffer.
function M.set_extmark(bm, bufnr)
  if bm.type == "file" then
    return
  end
  local buf = bufnr or M.get_buf_for_path(bm.path)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  local count = vim.api.nvim_buf_line_count(buf)
  local line0 = math.max(0, (bm.line or 1) - 1)
  if line0 > count - 1 then
    line0 = math.max(0, count - 1)
  end

  local col0 = 0
  if bm.type == "location" then
    col0 = math.max(0, (bm.col or 1) - 1)
  end
  local linetext = vim.api.nvim_buf_get_lines(buf, line0, line0 + 1, false)[1] or ""
  if col0 > #linetext then
    col0 = #linetext
  end

  local opts = { right_gravity = false }
  local signs = config.options.signs
  if signs and signs.enable then
    local cfg = (bm.type == "location") and signs.location or signs.line
    if cfg and cfg.text and cfg.text ~= "" then
      opts.sign_text = cfg.text
      opts.sign_hl_group = cfg.texthl
    end
  end

  -- Drop a stale extmark on this same buffer first.
  if bm._extmark and bm._extmark.buf == buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, M.ns, bm._extmark.id)
  end

  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, line0, col0, opts)
  if not ok then
    -- Older Neovim may reject sign_* keys; retry without signs so tracking
    -- still works.
    opts.sign_text, opts.sign_hl_group = nil, nil
    ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, line0, col0, opts)
  end
  if ok then
    bm._extmark = { buf = buf, id = id }
  end
end

--- Pull the current line/col from a live extmark back into the record.
function M.sync_from_extmark(bm)
  local em = bm._extmark
  if not em then
    return
  end
  if not vim.api.nvim_buf_is_valid(em.buf) then
    bm._extmark = nil
    return
  end
  local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, em.buf, M.ns, em.id, {})
  if ok and pos and pos[1] ~= nil then
    bm.line = pos[1] + 1
    if bm.type == "location" then
      bm.col = pos[2] + 1
    end
  end
end

function M.sync_all()
  for _, bm in ipairs(M.bookmarks) do
    M.sync_from_extmark(bm)
  end
end

function M.del_extmark(bm)
  local em = bm._extmark
  if em and vim.api.nvim_buf_is_valid(em.buf) then
    pcall(vim.api.nvim_buf_del_extmark, em.buf, M.ns, em.id)
  end
  bm._extmark = nil
end

--- Attach extmarks for any bookmarks belonging to a freshly-loaded buffer.
function M.attach_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  local path = M.normalize(name)
  for _, bm in ipairs(M.bookmarks) do
    if bm.type ~= "file" and bm.path == path then
      local live = bm._extmark and bm._extmark.buf == bufnr
      if not live then
        M.set_extmark(bm, bufnr)
      end
    end
  end
end

----------------------------------------------------------------------
-- persistence
----------------------------------------------------------------------

function M.save()
  M.sync_all()
  local data = {}
  for _, bm in ipairs(M.bookmarks) do
    table.insert(data, {
      id = bm.id,
      type = bm.type,
      path = bm.path,
      line = bm.line,
      col = bm.col,
      label = bm.label,
      created_at = bm.created_at,
    })
  end

  local path = config.options.storage_path
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    pcall(vim.fn.mkdir, dir, "p")
  end

  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    return false
  end
  local fd = io.open(path, "w")
  if not fd then
    return false
  end
  fd:write(json)
  fd:close()
  return true
end

function M.load()
  M.bookmarks = {}
  local path = config.options.storage_path
  local fd = io.open(path, "r")
  if not fd then
    return
  end
  local content = fd:read("*a")
  fd:close()
  if not content or content == "" then
    return
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return
  end
  for _, bm in ipairs(data) do
    if type(bm) == "table" and bm.path and bm.type then
      bm._extmark = nil
      table.insert(M.bookmarks, bm)
    end
  end
  -- Re-attach extmarks for buffers already open.
  for _, bm in ipairs(M.bookmarks) do
    M.set_extmark(bm)
  end
end

----------------------------------------------------------------------
-- CRUD
----------------------------------------------------------------------

--- Match an existing bookmark of the same identity (used to avoid duplicates).
function M.find_duplicate(bm)
  for _, e in ipairs(M.bookmarks) do
    if e.type == bm.type and e.path == bm.path then
      if bm.type == "file" then
        return e
      elseif bm.type == "line" and e.line == bm.line then
        return e
      elseif bm.type == "location" and e.line == bm.line and e.col == bm.col then
        return e
      end
    end
  end
  return nil
end

--- Add a bookmark. Returns (bookmark, status) where status is
--- "added" or "exists" (when an identical bookmark was already present).
function M.add(bm)
  bm.path = M.normalize(bm.path)
  if not bm.path then
    return nil, "invalid path"
  end

  local dup = M.find_duplicate(bm)
  if dup then
    return dup, "exists"
  end

  bm.id = bm.id or gen_id()
  bm.created_at = bm.created_at or os.time()
  table.insert(M.bookmarks, bm)
  M.set_extmark(bm)
  if config.options.auto_save then
    M.save()
  end
  return bm, "added"
end

function M.get(id)
  for _, bm in ipairs(M.bookmarks) do
    if bm.id == id then
      return bm
    end
  end
  return nil
end

function M.delete(id)
  for i, bm in ipairs(M.bookmarks) do
    if bm.id == id then
      M.del_extmark(bm)
      table.remove(M.bookmarks, i)
      if config.options.auto_save then
        M.save()
      end
      return true
    end
  end
  return false
end

--- Delete every bookmark, or only those of a given type when `filter_type`
--- is "file" | "line" | "location".
function M.delete_all(filter_type)
  local kept, removed = {}, 0
  for _, bm in ipairs(M.bookmarks) do
    if filter_type and bm.type ~= filter_type then
      table.insert(kept, bm)
    else
      M.del_extmark(bm)
      removed = removed + 1
    end
  end
  M.bookmarks = kept
  if config.options.auto_save then
    M.save()
  end
  return removed
end

--- Return a filtered, position-synced array of bookmarks.
--- `filter_type` may be nil/"all" or a concrete type.
function M.list(filter_type)
  M.sync_all()
  local out = {}
  for _, bm in ipairs(M.bookmarks) do
    if not filter_type or filter_type == "all" or bm.type == filter_type then
      table.insert(out, bm)
    end
  end
  return out
end

return M
