--- Persistent notification history with a toggleable floating window.
---
--- Usage (inside Extension.setup):
---
---   local nh = require("codecompanion._extensions.tiktoken.notify_history")
---   nh.setup({ max_entries = 100, keymap = "<leader>tt" })
---
---   -- Send a notification (persists it AND calls the real vim.notify):
---   nh.notify("some message", vim.log.levels.INFO, { title = "Token Breakdown" })
---
---   -- Toggle the history window from elsewhere:
---   nh.toggle()
---
--- The module never patches the global `vim.notify`; callers explicitly route
--- their notifications through `nh.notify()`.  This keeps the surface minimal
--- and avoids surprising other plugins.
---
---@class TiktokenNotifyHistory
local M = {}

--- @class TiktokenNotifyHistory.Entry
--- @field timestamp string  Wall-clock timestamp, e.g. "14:32:07"
--- @field level     integer vim.log.levels value
--- @field title     string  Notification title (may be empty)
--- @field message   string  Full notification body

--- @type TiktokenNotifyHistory.Entry[]
local _history = {}

--- @type integer  Maximum entries kept in the ring buffer.
local _max_entries = 200

--- @type integer|nil  Floating window handle (nil when closed).
local _win = nil

--- @type integer|nil  Buffer backing the floating window.
local _buf = nil

--- @type table  Namespace for extmark-based highlights.
local _ns = vim.api.nvim_create_namespace("tiktoken_notify_history")

--- Map a vim.log.levels integer to a short human-readable label.
--- @param level integer
--- @return string
local function level_label(level)
  local map = {
    [vim.log.levels.TRACE] = "TRACE",
    [vim.log.levels.DEBUG] = "DEBUG",
    [vim.log.levels.INFO]  = "INFO ",
    [vim.log.levels.WARN]  = "WARN ",
    [vim.log.levels.ERROR] = "ERROR",
    [vim.log.levels.OFF]   = "OFF  ",
  }
  return map[level] or "INFO "
end

--- Map a vim.log.levels integer to a highlight group name.
--- @param level integer
--- @return string
local function level_hl(level)
  local map = {
    [vim.log.levels.TRACE] = "Comment",
    [vim.log.levels.DEBUG] = "Comment",
    [vim.log.levels.INFO]  = "DiagnosticInfo",
    [vim.log.levels.WARN]  = "DiagnosticWarn",
    [vim.log.levels.ERROR] = "DiagnosticError",
    [vim.log.levels.OFF]   = "Comment",
  }
  return map[level] or "Normal"
end

--- Compute floating window dimensions and position (centered, 80% width/height).
--- @return { row: integer, col: integer, width: integer, height: integer }
local function win_geometry()
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local total_w = ui.width
  local total_h = ui.height
  local width  = math.max(60, math.floor(total_w * 0.80))
  local height = math.max(10, math.floor(total_h * 0.75))
  local row    = math.floor((total_h - height) / 2)
  local col    = math.floor((total_w - width) / 2)
  return { row = row, col = col, width = width, height = height }
end

--- Build the list of display lines for all history entries.
--- Returns the lines table and a parallel list of (line_index, highlight_group)
--- pairs for the header of each entry.
--- @return string[], {line: integer, hl: string}[]
local function build_lines()
  local lines = {}
  local hls   = {}  -- { line = 0-based index, hl = group }

  if #_history == 0 then
    lines[1] = "  (no notifications yet)"
    return lines, hls
  end

  for i, entry in ipairs(_history) do
    local sep = string.rep("─", 60)
    -- Header: index / timestamp / level / title
    local header = string.format(
      " [%d]  %s  %s  %s",
      i,
      entry.timestamp,
      level_label(entry.level),
      entry.title ~= "" and ("« " .. entry.title .. " »") or ""
    )
    table.insert(lines, sep)
    local header_line = #lines  -- 1-based; nvim_buf_add_highlight wants 0-based
    table.insert(hls, { line = header_line - 1, hl = level_hl(entry.level) })
    table.insert(lines, header)

    -- Body: each line of the message, indented
    for _, body_line in ipairs(vim.split(entry.message, "\n", { plain = true })) do
      table.insert(lines, "  " .. body_line)
    end
  end
  -- Final separator
  table.insert(lines, string.rep("─", 60))

  return lines, hls
end

--- Redraw the contents of an open history window.
local function redraw()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then
    return
  end

  local lines, hls = build_lines()

  vim.api.nvim_buf_set_option(_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(_buf, "modifiable", false)

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(_buf, _ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(_buf, _ns, h.hl, h.line, 0, -1)
  end

  -- Scroll to bottom in all windows displaying this buffer
  if _win and vim.api.nvim_win_is_valid(_win) then
    local line_count = vim.api.nvim_buf_line_count(_buf)
    vim.api.nvim_win_set_cursor(_win, { line_count, 0 })
  end
end

--- Open the floating history window.
local function open_window()
  if _win and vim.api.nvim_win_is_valid(_win) then
    -- Already open — just bring it into focus.
    vim.api.nvim_set_current_win(_win)
    return
  end

  -- Create (or reuse) the backing buffer.
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then
    _buf = vim.api.nvim_create_buf(false, true)  -- unlisted, scratch
    vim.api.nvim_buf_set_name(_buf, "Tiktoken Notify History")
    vim.api.nvim_buf_set_option(_buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(_buf, "swapfile", false)
    vim.api.nvim_buf_set_option(_buf, "filetype", "tiktoken_history")
    vim.api.nvim_buf_set_option(_buf, "modifiable", false)
  end

  local g = win_geometry()
  _win = vim.api.nvim_open_win(_buf, true, {
    relative = "editor",
    row      = g.row,
    col      = g.col,
    width    = g.width,
    height   = g.height,
    style    = "minimal",
    border   = "rounded",
    title    = " Tiktoken Notify History ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(_win, "wrap", false)
  vim.api.nvim_win_set_option(_win, "cursorline", true)
  vim.api.nvim_win_set_option(_win, "winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder")

  -- Close on <Esc> or q
  for _, key in ipairs({ "<Esc>", "q" }) do
    vim.api.nvim_buf_set_keymap(_buf, "n", key, "", {
      noremap = true,
      silent  = true,
      callback = function()
        M.close()
      end,
    })
  end

  -- Automatically close when focus leaves the window.
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer  = _buf,
    once    = true,
    callback = function()
      M.close()
    end,
  })

  redraw()
end

--- Close the floating history window (does not destroy the buffer or history).
function M.close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
end

--- Toggle the floating history window open/closed.
function M.toggle()
  if _win and vim.api.nvim_win_is_valid(_win) then
    M.close()
  else
    open_window()
  end
end

--- Record a notification in the history and forward it to the real vim.notify.
---
--- @param msg   string   Notification body text.
--- @param level integer  vim.log.levels value (default INFO).
--- @param opts  table    Optional notify options (e.g. { title = "..." }).
function M.notify(msg, level, opts)
  level = level or vim.log.levels.INFO
  opts  = opts  or {}

  -- Persist the entry.
  local entry = {
    timestamp = os.date("%H:%M:%S"),
    level     = level,
    title     = opts.title or "",
    message   = msg,
  }
  table.insert(_history, entry)

  -- Trim the ring buffer if needed.
  while #_history > _max_entries do
    table.remove(_history, 1)
  end

  -- If the window is currently open, live-update it.
  if _win and vim.api.nvim_win_is_valid(_win) then
    redraw()
  end

  -- Delegate to the real vim.notify.
  vim.notify(msg, level, opts)
end

--- Clear all stored history entries and redraw the window if open.
function M.clear()
  _history = {}
  if _win and vim.api.nvim_win_is_valid(_win) then
    redraw()
  end
end

--- Return a shallow copy of the current history list (for testing / export).
--- @return TiktokenNotifyHistory.Entry[]
function M.get_history()
  local copy = {}
  for i, e in ipairs(_history) do
    copy[i] = e
  end
  return copy
end

--- Configure the module and optionally register a global keymap to toggle.
---
--- @param opts table  Optional settings:
---   - `max_entries` (integer, default 200): ring-buffer capacity.
---   - `keymap` (string|false): normal-mode key to toggle window.
---       Set to `false` to skip registration entirely.
---       Default is `"<leader>tt"`.
function M.setup(opts)
  opts = opts or {}

  if type(opts.max_entries) == "number" and opts.max_entries > 0 then
    _max_entries = opts.max_entries
  end

  local keymap = opts.keymap
  if keymap == nil then
    keymap = "<leader>tt"
  end
  if keymap ~= false and keymap ~= "" then
    vim.keymap.set("n", keymap, function()
      M.toggle()
    end, {
      noremap = true,
      silent  = true,
      desc    = "Toggle tiktoken notify history window",
    })
  end
end

return M
