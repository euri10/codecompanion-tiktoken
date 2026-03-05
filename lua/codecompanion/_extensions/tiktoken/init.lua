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

  --- Per-buffer snapshot taken at CodeCompanionRequestStarted.
  --- Wall-clock time is captured at the moment the HTTP request fires so that
  --- generation t/s reflects actual API latency rather than any pre-request lag.
  --- @type table<integer, { tokens: integer, time_ms: integer }>
  local request_snapshots = {}

  --- Render a single llama.cpp-style stat line.
  --- @param tokens integer
  --- @param elapsed_s number
  --- @param tps number
  --- @param label string  e.g. "prompt" or "generation"
  --- @return string
  local function stat_line(tokens, elapsed_s, tps, label)
    return string.format("≈ %d tokens  ⊙ %.2fs  ↺ %.2f t/s  (%s)", tokens, elapsed_s, tps, label)
  end

  --- Retrieve the chat object from event data, returning nil silently on failure.
  --- @param args table  autocmd callback args
  --- @return table|nil
  local function chat_from_args(args)
    local bufnr = args.data and args.data.bufnr or 0
    return require("codecompanion").buf_get_chat(bufnr), bufnr
  end

  --- Count tokens for the current message list and show a prompt-only notification.
  --- @param chat table  CodeCompanion chat object
  --- @param label string  event label for the header line
  local function notify_prompt_tokens(chat, label)
    local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
    --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number }
    local result = tiktoken.count_messages(chat.messages, model_name)
    local lines = {
      "-------------------------------",
      string.format("⊛ %s  [%s]", model_name, label),
      stat_line(result.tokens, result.elapsed_ms / 1000.0, result.tokens_per_sec, "prompt"),
      "-------------------------------",
    }
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
      local chat, _ = chat_from_args(args)
      if not chat then return end
      notify_prompt_tokens(chat, "submitted")
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionRequestStarted
  -- Capture a snapshot (token count + wall-clock time) at the exact moment the
  -- HTTP request fires.  Using this event instead of ChatSubmitted means the
  -- generation t/s measurement excludes any pre-request processing time.
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
        tokens  = result.tokens,
        time_ms = vim.uv.now(),
      }
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatDone
  -- Show both prompt and generation stats.  Generation delta is computed from
  -- the snapshot recorded at RequestStarted so t/s reflects true API latency.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatDone",
    callback = function(args)
      local chat, bufnr = chat_from_args(args)
      if not chat then return end
      local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
      --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number }
      local result = tiktoken.count_messages(chat.messages, model_name)
      local lines = {
        "-------------------------------",
        string.format("⊛ %s  [done]", model_name),
        stat_line(result.tokens, result.elapsed_ms / 1000.0, result.tokens_per_sec, "prompt"),
      }
      local snap = request_snapshots[bufnr]
      if snap then
        local wall_elapsed_s = (vim.uv.now() - snap.time_ms) / 1000.0
        local gen_tokens = result.tokens - snap.tokens
        if gen_tokens > 0 and wall_elapsed_s > 0 then
          local gen_tps = gen_tokens / wall_elapsed_s
          table.insert(lines, stat_line(gen_tokens, wall_elapsed_s, gen_tps, "generation"))
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
      --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number }
      local result = tiktoken.count_messages(chat.messages, model_name)
      local lines = {
        "-------------------------------",
        string.format("⊛ %s  [stopped]", model_name),
        stat_line(result.tokens, result.elapsed_ms / 1000.0, result.tokens_per_sec, "prompt"),
      }
      if snap then
        local wall_elapsed_s = (vim.uv.now() - snap.time_ms) / 1000.0
        local gen_tokens = result.tokens - snap.tokens
        if gen_tokens > 0 and wall_elapsed_s > 0 then
          table.insert(lines, stat_line(gen_tokens, wall_elapsed_s, gen_tokens / wall_elapsed_s, "partial generation"))
        end
      end
      table.insert(lines, "-------------------------------")
      vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN, { title = "Token Breakdown (stopped)" })
    end,
  })

  -- ---------------------------------------------------------------------------
  -- CodeCompanionChatClosed
  -- Clean up any lingering snapshot when a chat buffer is permanently closed.
  -- ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatClosed",
    callback = function(args)
      local bufnr = args.data and args.data.bufnr or 0
      request_snapshots[bufnr] = nil
    end,
  })
end

-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
