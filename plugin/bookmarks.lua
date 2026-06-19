-- bookmarks.nvim :: user commands.
if vim.g.loaded_bookmarks_nvim then
  return
end
vim.g.loaded_bookmarks_nvim = true

local function api()
  return require("bookmarks")
end

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

-- Normalize plural / singular tab names from command args.
local KIND = {
  all = "all",
  file = "file",
  files = "file",
  line = "line",
  lines = "line",
  location = "location",
  locations = "location",
}

local function complete_kinds()
  return { "all", "files", "lines", "locations" }
end

cmd("BookmarkFile", function(o)
  api().bookmark_file(nil, o.args ~= "" and o.args or nil)
end, { nargs = "?", desc = "Bookmark the current file (optional label)" })

cmd("BookmarkLine", function(o)
  api().bookmark_line(o.args ~= "" and o.args or nil)
end, { nargs = "?", desc = "Bookmark the current line (optional label)" })

cmd("BookmarkLocation", function(o)
  api().bookmark_location(o.args ~= "" and o.args or nil)
end, { nargs = "?", desc = "Bookmark the cursor location (optional label)" })

cmd("BookmarkToggleLine", function()
  api().toggle_line()
end, { desc = "Toggle a line bookmark on the current line" })

cmd("BookmarkToggleFile", function()
  api().toggle_file()
end, { desc = "Toggle a file bookmark for the current buffer" })

cmd("Bookmarks", function(o)
  local kind = (o.args ~= "" and KIND[o.args]) or "all"
  api().open(kind)
end, {
  nargs = "?",
  complete = complete_kinds,
  desc = "Open the bookmarks popup (all|files|lines|locations)",
})

cmd("BookmarkNext", function(o)
  local kind = (o.args ~= "" and KIND[o.args]) or nil
  api().jump_next(kind)
end, {
  nargs = "?",
  complete = complete_kinds,
  desc = "Jump to next bookmark (all|files|lines|locations)",
})

cmd("BookmarkPrev", function(o)
  local kind = (o.args ~= "" and KIND[o.args]) or nil
  api().jump_prev(kind)
end, {
  nargs = "?",
  complete = complete_kinds,
  desc = "Jump to previous bookmark (all|files|lines|locations)",
})

cmd("BookmarksClear", function(o)
  if o.args == "" then
    local n = api().clear(nil)
    vim.notify("[bookmarks] cleared " .. n .. " bookmark(s)")
    return
  end
  local kind = KIND[o.args]
  if not kind then
    vim.notify("[bookmarks] unknown kind: " .. o.args, vim.log.levels.WARN)
    return
  end
  local n = api().clear(kind == "all" and nil or kind)
  vim.notify("[bookmarks] cleared " .. n .. " " .. o.args)
end, {
  nargs = "?",
  complete = complete_kinds,
  desc = "Clear bookmarks (all|files|lines|locations)",
})
