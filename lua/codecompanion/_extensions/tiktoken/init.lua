---@class CodeCompanion.Extension
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.your_extension
local Extension = {}

---Setup the extension
---@param opts table Configuration options
function Extension.setup(opts)
  -- Initialize extension
  -- Add actions, keymaps etc.
  local tiktoken = require("tiktoken")

  -- Debug: verify Rust module loaded correctly
  if not tiktoken.count_text then
    vim.notify("Error: tiktoken Rust module not loaded correctly", vim.log.levels.ERROR)
    return
  end

  local relevant_events = {
    "CodeCompanionChatCreated",
    "CodeCompanionChatOpened",
    "CodeCompanionChatSubmitted",
    "CodeCompanionChatDone",
    "CodeCompanionToolApprovalRequested",
  }

  for _, event in ipairs(relevant_events) do
    vim.api.nvim_create_autocmd("User", {
      pattern = event,
        callback = function(args)
        local chat = require("codecompanion").buf_get_chat(args.data and args.data.bufnr or 0)
        if not chat then
          vim.notify("Token breakdown: chat not found", vim.log.levels.WARN)
          return
        end
        local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
        --- @type { tokens: integer, elapsed_ms: number, tokens_per_sec: number }
        local result = tiktoken.count_messages(chat.messages, model_name)
        local elapsed_s = result.elapsed_ms / 1000.0
        local lines = {
          "-------------------------------",
          string.format("----- %s -----", event),
          string.format("⊛ %s", model_name),
          string.format("≈ %d tokens  ⊙ %.2fs  ↺ %.2f t/s", result.tokens, elapsed_s, result.tokens_per_sec),
          "-------------------------------",
        }
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
      end,
    })
  end
end

-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
