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

        local total_tokens = 0
        local total_estimated_tokens = 0

        for _, message in ipairs(chat.messages) do
          local count = 0
          local estimated = 0
          if not message.content then
            count = 0
            estimated = 0
          else
            count = tiktoken.count_text(message.content, model_name)
            if message._meta and message._meta.estimated_tokens then
              estimated = message._meta.estimated_tokens
            else
              estimated = 0
            end
          end
          total_tokens = total_tokens + count
          total_estimated_tokens = total_estimated_tokens + estimated
        end
        -- Notify UI only (no floating window)
        local lines = {}
        table.insert(lines, "-------------------------------")
	table.insert(lines, string.format("----- %s -----", event))
        table.insert(lines, string.format("Total: %d | Estimated: %d", total_tokens, total_estimated_tokens))
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
      end,
    })
  end
end

-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
