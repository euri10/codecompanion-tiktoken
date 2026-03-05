---@class CodeCompanion.Extension
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.your_extension
local Extension = {}

---Setup the extension
---@param opts table Configuration options
function Extension.setup(opts)
  local tiktoken = require("tiktoken")

  -- Verify Rust module loaded correctly.
  if not tiktoken.count_text then
    vim.notify("Error: tiktoken Rust module not loaded correctly", vim.log.levels.ERROR)
    return
  end

  --- Per-buffer tiktoken count, updated after each completed turn.
  --- Used to annotate the built-in heuristic count in the chat header.
  --- @type table<integer, integer>
  local tiktoken_counts = {}

  -- Override the built-in token_count display to show both the heuristic
  -- (codecompanion native) count and the accurate tiktoken count side-by-side.
  -- e.g. "(123 tokens · tiktoken: 117)"
  -- nvim_get_current_buf() is safe here: display_tokens is always called
  -- synchronously from within the chat buffer's response handling.
  do
    local cc_config = require("codecompanion.config")
    local orig = cc_config.display.chat.token_count
    cc_config.display.chat.token_count = function(builtin_tokens, adapter)
      local bufnr = vim.api.nvim_get_current_buf()
      local tkt = tiktoken_counts[bufnr]
      if tkt then
        local diff = tkt - builtin_tokens
        local pct = builtin_tokens > 0
          and string.format(", %s%d%%", diff >= 0 and "+" or "", math.floor(diff / builtin_tokens * 100 + 0.5))
          or ""
        return string.format(" (%d tokens · tiktoken: %d%s)", builtin_tokens, tkt, pct)
      end
      return orig(builtin_tokens, adapter)
    end
  end

  --- Per-buffer snapshot taken at CodeCompanionRequestStarted (or RequestStreaming).
  --- Wall-clock time is captured at the moment the HTTP request fires so that
  --- generation t/s reflects actual API latency rather than any pre-request lag.
  --- @type table<integer, { tokens: integer, time_ms: integer, is_streaming: boolean }>
  local request_snapshots = {}

  --- Per-buffer snapshot taken at CodeCompanionInlineStarted.
  --- @type table<integer, { tokens: integer, time_ms: integer, model: string }>
  local inline_snapshots = {}

  --- Per-buffer snapshot taken at CodeCompanionToolsStarted (the aggregate cycle event).
  --- Tracks the token count and wall-clock time at the start of the whole tool cycle,
  --- plus a running count of individual tools that have started within it.
  --- @type table<integer, { tokens: integer, time_ms: integer, tool_count: integer }>
  local tools_cycle_snapshots = {}

  --- Format a per-role token breakdown into display lines.
  --- Only rows with >0 tokens are shown.  Percentages are relative to `total`.
  --- @param breakdown table  The `breakdown` sub-table returned by `count_messages`
  --- @param total integer    Grand total token count for percentage calculation
  --- @return string[]        Extra lines to append before the closing separator
  local function format_breakdown(breakdown, total)
    if not breakdown or total == 0 then return {} end

    local rows = {
      { label = "system",   value = breakdown.system    or 0 },
      { label = "user",     value = breakdown.user      or 0 },
      { label = "assistant",value = breakdown.assistant or 0 },
      { label = "tool",     value = breakdown.tool      or 0 },
      { label = "overhead", value = breakdown.overhead  or 0 },
    }

    local lines = {}
    for _, row in ipairs(rows) do
      if row.value > 0 then
        local pct = math.floor(row.value / total * 100 + 0.5)
        table.insert(lines, string.format(
          "  %-9s │ %5d  (%d%%)", row.label, row.value, pct
        ))
      end
    end

    -- System sub-tag breakdown (only if ≥2 distinct tags)
    local tags = breakdown.system_tags
    if tags then
      local tag_rows = {}
      for tag, count in pairs(tags) do
        if count > 0 then
          table.insert(tag_rows, { label = tag, value = count })
        end
      end
      table.sort(tag_rows, function(a, b) return a.value > b.value end)
      if #tag_rows >= 2 then
        table.insert(lines, "  system breakdown:")
        for _, row in ipairs(tag_rows) do
          local pct = math.floor(row.value / (breakdown.system or 1) * 100 + 0.5)
          table.insert(lines, string.format(
            "    %-28s │ %5d  (%d%%)", row.label, row.value, pct
          ))
        end
      end
    end

    return lines
  end


  --- @param tokens integer
  --- @param elapsed_s number
  --- @param tps number
  --- @param label string  e.g. "prompt" or "generation"
  --- @param total_estimated integer|nil
  --- @return string
  local function stat_line(tokens, elapsed_s, tps, label, total_estimated)
    if total_estimated and total_estimated > 0 then
      return string.format(
        "≈ %d tokens (heuristic total: %d)  ⊙ %.2fs  ↺ %.2f t/s  (%s)",
        tokens, total_estimated, elapsed_s, tps, label
      )
    else
      return string.format(
        "≈ %d tokens  ⊙ %.2fs  ↺ %.2f t/s  (%s)",
        tokens, elapsed_s, tps, label
      )
    end
  end

  --- Retrieve the chat object and bufnr from autocmd event data.
  --- Returns nil on failure; all callers guard against nil.
  --- @param args table  autocmd callback args
  --- @return table|nil chat, integer bufnr
  local function chat_from_args(args)
    local bufnr = args.data and args.data.bufnr or 0
    return require("codecompanion").buf_get_chat(bufnr), bufnr
  end

  --- Count tokens for the current message list and show a prompt-only notification.
  --- @param chat table  CodeCompanion chat object
  --- @param label string  event label for the header line
  local function notify_prompt_tokens(chat, label)
    local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
    --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number, total_estimated: integer|nil, breakdown: table|nil }
    local result = tiktoken.count_messages(chat.messages, model_name)
    local lines = {
      "-------------------------------",
      string.format("⊛ %s  [%s]", model_name, label),
      stat_line(result.tokens, result.elapsed_ms / 1000.0, result.tokens_per_sec, "prompt", result.total_estimated),
    }
    for _, l in ipairs(format_breakdown(result.breakdown, result.tokens)) do
      table.insert(lines, l)
    end
    table.insert(lines, "-------------------------------")
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
  end

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatOpened
  -- Show prompt token count whenever the user opens (or re-opens) a chat buffer.
  -- CodeCompanionChatCreated is intentionally omitted: messages are not yet
  -- populated when a brand-new chat is created.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatOpened",
    callback = function(args)
      local chat, _ = chat_from_args(args)
      if not chat or not chat.messages or #chat.messages == 0 then return end
      notify_prompt_tokens(chat, "opened")
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionToolApprovalRequested
  -- Show prompt size before the user decides whether to approve a tool call.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionToolApprovalRequested",
    callback = function(args)
      local chat, _ = chat_from_args(args)
      if not chat then return end
      notify_prompt_tokens(chat, "tool approval")
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatSubmitted
  -- Show prompt token count immediately when the user submits.  This gives
  -- fast feedback before the API responds.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatSubmitted",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      if not chat then return end
      -- Also update the header token cache so the extmark reflects the
      -- tiktoken count immediately on submit (before the response arrives).
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      local result = tiktoken.count_messages(chat.messages, model_name)
      tiktoken_counts[bufnr] = result.tokens
      notify_prompt_tokens(chat, "submitted")
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionRequestStarted
  -- Capture a baseline snapshot (token count + wall-clock time) at the exact
  -- moment any API request fires.  For streaming calls, RequestStreaming will
  -- fire shortly after and update is_streaming in place.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionRequestStarted",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      if not chat then return end
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number }
      local result = tiktoken.count_messages(chat.messages, model_name)
      request_snapshots[bufnr] = {
        tokens       = result.tokens,
        time_ms      = math.floor(vim.loop.hrtime() / 1e6),
        is_streaming = false,
      }
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionRequestStreaming
  -- Fires only for streaming API requests (after RequestStarted).  We annotate
  -- the existing snapshot so the Done/Stopped handlers can label generation
  -- stats as "streaming generation" vs plain "generation".
  -- If no RequestStarted snapshot exists yet (race), we create one here.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionRequestStreaming",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      if not chat then return end
      local snap = request_snapshots[bufnr]
      if snap then
        snap.is_streaming = true
      else
        -- Fallback: create snapshot if RequestStarted somehow did not fire first.
        local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
        local result = tiktoken.count_messages(chat.messages, model_name)
        request_snapshots[bufnr] = {
          tokens       = result.tokens,
          time_ms      = math.floor(vim.loop.hrtime() / 1e6),
          is_streaming = true,
        }
      end
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatDone
  -- Show both prompt and generation stats.  Generation delta is computed from
  -- the snapshot recorded at RequestStarted/RequestStreaming so t/s reflects
  -- true API latency.  The generation label notes whether it was streaming.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatDone",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      if not chat then return end
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number, total_estimated: integer|nil, breakdown: table|nil }
      local result = tiktoken.count_messages(chat.messages, model_name)
      tiktoken_counts[bufnr] = result.tokens
      local lines = {
        "-------------------------------",
        string.format("⊛ %s  [done]", model_name),
        stat_line(result.tokens, result.elapsed_ms / 1000.0, result.tokens_per_sec, "prompt", result.total_estimated),
      }
      for _, l in ipairs(format_breakdown(result.breakdown, result.tokens)) do
        table.insert(lines, l)
      end
      local snap = request_snapshots[bufnr]
      if snap then
        local wall_elapsed_s = (math.floor(vim.loop.hrtime() / 1e6) - snap.time_ms) / 1000.0
        local gen_tokens = result.tokens - snap.tokens
        if gen_tokens > 0 and wall_elapsed_s > 0 then
          local gen_label = snap.is_streaming and "streaming generation" or "generation"
          local gen_tps   = gen_tokens / wall_elapsed_s
          table.insert(lines, stat_line(gen_tokens, wall_elapsed_s, gen_tps, gen_label))
        end
        request_snapshots[bufnr] = nil
      end
      table.insert(lines, "-------------------------------")
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatStopped
  -- The user aborted the request mid-stream.  Show partial generation stats
  -- (if any tokens arrived) and clean up the snapshot.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatStopped",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      local snap = request_snapshots[bufnr]
      request_snapshots[bufnr] = nil

      if not chat then return end
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number, total_estimated: integer|nil, breakdown: table|nil }
      local result = tiktoken.count_messages(chat.messages, model_name)
      local lines = {
        "-------------------------------",
        string.format("⊛ %s  [stopped]", model_name),
        stat_line(result.tokens, result.elapsed_ms / 1000.0, result.tokens_per_sec, "prompt", result.total_estimated),
      }
      for _, l in ipairs(format_breakdown(result.breakdown, result.tokens)) do
        table.insert(lines, l)
      end
      if snap then
        local wall_elapsed_s = (math.floor(vim.loop.hrtime() / 1e6) - snap.time_ms) / 1000.0
        local gen_tokens = result.tokens - snap.tokens
        if gen_tokens > 0 and wall_elapsed_s > 0 then
          local partial_label = snap.is_streaming and "partial streaming" or "partial generation"
          table.insert(lines, stat_line(gen_tokens, wall_elapsed_s, gen_tokens / wall_elapsed_s, partial_label))
        end
      end
      table.insert(lines, "-------------------------------")
      vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN, { title = "Token Breakdown (stopped)" })
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatClosed
  -- Clean up any lingering snapshots when a chat buffer is permanently closed.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatClosed",
    callback = function(args)
      local bufnr = args.data and args.data.bufnr or 0
      request_snapshots[bufnr] = nil
      tools_cycle_snapshots[bufnr] = nil
      tiktoken_counts[bufnr] = nil
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionInlineStarted
  -- Capture the token count of the current buffer content and a wall-clock
  -- timestamp.  This lets InlineFinished compute how many tokens the inline
  -- edit generated and how fast it arrived.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionInlineStarted",
    callback = function(args)
      local bufnr = args.buf or 0
      -- Resolve model name from the event data if available, fall back to cl100k.
      local model_name = (args.data
        and args.data.adapter
        and args.data.adapter.model
        or "cl100k_base")
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")
      local token_count = tiktoken.count_text(content, model_name)
      inline_snapshots[bufnr] = {
        tokens   = token_count,
        time_ms  = math.floor(vim.loop.hrtime() / 1e6),
        model    = model_name,
      }
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionInlineFinished
  -- Count tokens in the (now-modified) buffer and display the delta — i.e.
  -- how many net tokens the inline edit added — plus generation t/s.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionInlineFinished",
    callback = function(args)
      local bufnr = args.buf or 0
      local snap = inline_snapshots[bufnr]
      inline_snapshots[bufnr] = nil

      local model_name = (args.data
        and args.data.adapter
        and args.data.adapter.model
        or (snap and snap.model or "cl100k_base"))
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")
      local new_tokens = tiktoken.count_text(content, model_name)

      local header = string.format("⊛ %s  [inline]", model_name)
      local info_lines = {
        "-------------------------------",
        header,
        string.format("≈ %d tokens  (buffer after edit)", new_tokens),
      }

      if snap then
        local wall_elapsed_s = (math.floor(vim.loop.hrtime() / 1e6) - snap.time_ms) / 1000.0
        local delta = new_tokens - snap.tokens
        local sign = delta >= 0 and "+" or ""
        table.insert(info_lines, string.format(
          "Δ %s%d tokens  ⊙ %.2fs  (inline delta)",
          sign, delta, wall_elapsed_s
        ))
      end

      table.insert(info_lines, "-------------------------------")
      vim.notify(
        table.concat(info_lines, "\n"),
        vim.log.levels.INFO,
        { title = "Token Breakdown (inline)" }
      )
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionToolsStarted
  -- Fired once when the tool-execution system starts for a chat turn (may run
  -- multiple individual tools sequentially).  We snapshot the token count and
  -- wall-clock time here so ToolsFinished can show the aggregate delta.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionToolsStarted",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      if not chat then return end
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      local result = tiktoken.count_messages(chat.messages, model_name)
      tools_cycle_snapshots[bufnr] = {
        tokens     = result.tokens,
        time_ms    = math.floor(vim.loop.hrtime() / 1e6),
        tool_count = 0,
      }
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionToolStarted
  -- Fired for each individual tool within the cycle.  We only increment the
  -- counter here — no notification to avoid per-tool spam.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionToolStarted",
    callback = function(args)
      local _, bufnr = chat_from_args(args)
      local snap = tools_cycle_snapshots[bufnr]
      if snap then
        snap.tool_count = snap.tool_count + 1
      end
    end,
  })

  -- CodeCompanionToolFinished — intentionally silent; summary shown at ToolsFinished.

  -- ---------------------------------------------------------------------------
  -- CodeCompanionToolsFinished
  -- Fired once after all tools in the cycle have completed.  Shows a single
  -- aggregate notification: total context delta, elapsed time, and tool count.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionToolsFinished",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      local snap = tools_cycle_snapshots[bufnr]
      tools_cycle_snapshots[bufnr] = nil

      if not chat then return end
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      local result = tiktoken.count_messages(chat.messages, model_name)

      local tool_count = snap and snap.tool_count or 0
      local tool_label = tool_count == 1 and "1 tool" or string.format("%d tools", tool_count)

      local info_lines = {
        "-------------------------------",
        string.format("⊛ %s  [tools done — %s]", model_name, tool_label),
        string.format("≈ %d tokens  (context after tools)", result.tokens),
      }

      if snap then
        local wall_elapsed_s = (math.floor(vim.loop.hrtime() / 1e6) - snap.time_ms) / 1000.0
        local delta = result.tokens - snap.tokens
        local sign  = delta >= 0 and "+" or ""
        table.insert(info_lines, string.format(
          "Δ %s%d tokens  ⊙ %.2fs  (tool cycle output)",
          sign, delta, wall_elapsed_s
        ))
      end

      table.insert(info_lines, "-------------------------------")
      vim.notify(
        table.concat(info_lines, "\n"),
        vim.log.levels.INFO,
        { title = "Token Breakdown (tools)" }
      )
    end,
  })
end

-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
