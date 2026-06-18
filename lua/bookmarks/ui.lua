-- bookmarks.nvim :: floating popup menu.
--
-- Renders a tabbed list (All / Files / Lines / Locations) of bookmarks and
-- handles in-popup actions: jump, delete one, delete all (current tab),
-- switch tab, close.

local config = require("bookmarks.config")
local store = require("bookmarks.store")

local M = {}

local ns = vim.api.nvim_create_namespace("bookmarks_ui")

local FILTERS = { "all", "file", "line", "location" }
local FILTER_LABEL = { all = "All", file = "Files", line = "Lines", location = "Locations" }
local TYPE_TAG = { file = "FILE", line = "LINE", location = " LOC" }
local TAG_HL = {
  file = "BookmarksUITagFile",
  line = "BookmarksUITagLine",
  location = "BookmarksUITagLocation",
}

local state = {
  buf = nil,
  win = nil,
  filter = "all",
  map = {}, -- 1-based lnum -> bookmark
  entry_lines = {}, -- sorted list of selectable lnums
}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function counts()
  local c = { file = 0, line = 0, location = 0 }
  for _, bm in ipairs(store.bookmarks) do
    c[bm.type] = (c[bm.type] or 0) + 1
  end
  c.all = c.file + c.line + c.location
  return c
end

local function nearest_entry(target)
  local lines = state.entry_lines
  if #lines == 0 then
    return nil
  end
  for _, l in ipairs(lines) do
    if l >= target then
      return l
    end
  end
  return lines[#lines]
end

local function is_open()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

----------------------------------------------------------------------
-- rendering
----------------------------------------------------------------------

local function build(width)
  local c = counts()
  local lines, hls, map, entry_lines = {}, {}, {}, {}

  -- Tab header.
  local header = " "
  for _, f in ipairs(FILTERS) do
    local seg
    if f == "all" then
      seg = string.format("[ %s ] ", FILTER_LABEL[f])
    else
      seg = string.format(" %s(%d) ", FILTER_LABEL[f], c[f])
    end
    local start = #header
    header = header .. seg
    table.insert(hls, {
      line = 0,
      col_start = start,
      col_end = #header,
      hl = (state.filter == f) and "BookmarksUITabActive" or "BookmarksUITab",
    })
  end
  table.insert(lines, header)

  -- Separator.
  local sep = string.rep("─", math.max(1, width))
  table.insert(lines, sep)
  table.insert(hls, { line = #lines - 1, col_start = 0, col_end = #sep, hl = "BookmarksUISep" })

  -- Entries.
  local items = store.list(state.filter)
  local order = { file = 1, line = 2, location = 3 }
  table.sort(items, function(a, b)
    if a.type ~= b.type then
      return order[a.type] < order[b.type]
    end
    if a.path ~= b.path then
      return a.path < b.path
    end
    return (a.line or 0) < (b.line or 0)
  end)

  if #items == 0 then
    table.insert(lines, "  (no bookmarks)")
    table.insert(hls, { line = #lines - 1, col_start = 0, col_end = 16, hl = "BookmarksUIHint" })
  else
    for _, bm in ipairs(items) do
      local tag = TYPE_TAG[bm.type] or "????"
      local pos = ""
      if bm.type == "line" then
        pos = ":" .. tostring(bm.line or "?")
      elseif bm.type == "location" then
        pos = tostring(bm.line or "?") .. ":" .. tostring(bm.col or "?")
      end
      local fname = vim.fn.fnamemodify(bm.path, ":t")
      local dir = vim.fn.fnamemodify(bm.path, ":~:.")
      local label = bm.label and ("  " .. bm.label) or ""

      local s = "  "
      local tag_s = #s
      s = s .. tag
      local tag_e = #s
      s = s .. "  "
      local pos_s = #s
      s = s .. string.format("%-6s", pos)
      local pos_e = #s
      s = s .. "  "
      local name_s = #s
      s = s .. fname
      local name_e = #s
      s = s .. "  "
      local dir_s = #s
      s = s .. dir
      local dir_e = #s
      local label_s = #s
      s = s .. label
      local label_e = #s

      table.insert(lines, s)
      local ln = #lines - 1
      map[#lines] = bm
      table.insert(entry_lines, #lines)

      table.insert(hls, { line = ln, col_start = tag_s, col_end = tag_e, hl = TAG_HL[bm.type] })
      table.insert(hls, { line = ln, col_start = pos_s, col_end = pos_e, hl = "BookmarksUIPos" })
      table.insert(hls, { line = ln, col_start = name_s, col_end = name_e, hl = "BookmarksUIName" })
      table.insert(hls, { line = ln, col_start = dir_s, col_end = dir_e, hl = "BookmarksUIPath" })
      if label ~= "" then
        table.insert(hls, { line = ln, col_start = label_s, col_end = label_e, hl = "BookmarksUILabel" })
      end
    end
  end

  -- Footer.
  table.insert(lines, sep)
  table.insert(hls, { line = #lines - 1, col_start = 0, col_end = #sep, hl = "BookmarksUISep" })
  local hint = "  <CR> jump   d delete   D clear tab   <Tab> next   0/1/2/3 filter   q close"
  table.insert(lines, hint)
  table.insert(hls, { line = #lines - 1, col_start = 0, col_end = #hint, hl = "BookmarksUIHint" })

  return lines, hls, map, entry_lines
end

--- Re-draw the popup. `target_line` optionally requests a cursor row to land
--- nearest to (used after deletions); otherwise the first entry is selected.
function M.render(target_line)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local width = is_open() and vim.api.nvim_win_get_width(state.win) or 60

  local lines, hls, map, entry_lines = build(width)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, h.line, h.col_start, {
      end_row = h.line,
      end_col = h.col_end,
      hl_group = h.hl,
    })
  end

  state.map = map
  state.entry_lines = entry_lines

  if is_open() then
    local lnum
    if target_line then
      lnum = nearest_entry(target_line)
    elseif #entry_lines > 0 then
      lnum = entry_lines[1]
    end
    if lnum then
      pcall(vim.api.nvim_win_set_cursor, state.win, { lnum, 0 })
    end
  end
end

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------

local function current_bookmark()
  if not is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.map[lnum], lnum
end

function M.close()
  if is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win, state.buf = nil, nil
end

function M.action_jump()
  local bm = current_bookmark()
  if not bm then
    return
  end
  M.close()
  require("bookmarks").jump(bm.id)
end

function M.action_delete()
  local bm, lnum = current_bookmark()
  if not bm then
    return
  end
  store.delete(bm.id)
  M.render(lnum)
end

function M.action_delete_all()
  local c = counts()
  local n = (state.filter == "all") and c.all or c[state.filter]
  if n == 0 then
    return
  end
  local what = (state.filter == "all") and "all bookmarks"
    or (FILTER_LABEL[state.filter]:lower() .. " bookmarks")
  local choice = vim.fn.confirm(string.format("Delete %d %s?", n, what), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  store.delete_all(state.filter == "all" and nil or state.filter)
  M.render()
end

function M.set_filter(f)
  if vim.tbl_contains(FILTERS, f) then
    state.filter = f
    M.render()
  end
end

function M.cycle(dir)
  local idx = 1
  for i, f in ipairs(FILTERS) do
    if f == state.filter then
      idx = i
      break
    end
  end
  idx = ((idx - 1 + dir) % #FILTERS) + 1
  M.set_filter(FILTERS[idx])
end

----------------------------------------------------------------------
-- window setup
----------------------------------------------------------------------

local function setup_keymaps(buf)
  local km = config.options.keymaps
  local function mapset(lhs, fn)
    local opts = { buffer = buf, nowait = true, silent = true }
    if type(lhs) == "table" then
      for _, k in ipairs(lhs) do
        vim.keymap.set("n", k, fn, opts)
      end
    elseif lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, fn, opts)
    end
  end

  mapset(km.jump, M.action_jump)
  mapset(km.delete, M.action_delete)
  mapset(km.delete_all, M.action_delete_all)
  mapset(km.close, M.close)
  mapset(km.next_tab, function() M.cycle(1) end)
  mapset(km.prev_tab, function() M.cycle(-1) end)
  mapset(km.filter_all, function() M.set_filter("all") end)
  mapset(km.filter_files, function() M.set_filter("file") end)
  mapset(km.filter_lines, function() M.set_filter("line") end)
  mapset(km.filter_locations, function() M.set_filter("location") end)
end

local function dimension(value, total, min)
  local n
  if value >= 1 then
    n = math.floor(value)
  else
    n = math.floor(total * value)
  end
  return math.max(n, min)
end

function M.open(filter)
  if filter and vim.tbl_contains(FILTERS, filter) then
    state.filter = filter
  end
  M.close()

  local ui = config.options.ui
  local total_w, total_h = vim.o.columns, vim.o.lines
  local width = dimension(ui.width or 0.6, total_w, 40)
  local height = dimension(ui.height or 0.6, total_h, 8)
  width = math.min(width, total_w - 2)
  height = math.min(height, total_h - 2)
  local row = math.floor((total_h - height) / 2 - 1)
  local col = math.floor((total_w - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  state.buf = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "bookmarks"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = ui.border or "rounded",
    title = ui.title or " Bookmarks ",
    title_pos = "center",
  })
  state.win = win
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  setup_keymaps(buf)
  M.render()
end

return M
