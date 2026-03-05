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
        local other_count = tiktoken.count_messages(chat.messages, model_name)
        -- Call llama.cpp-style output for chat.messages
        if tiktoken.llama_cpp_style_output then
          tiktoken.llama_cpp_style_output(chat.messages, model_name)
        end
        -- Notify UI only (no floating window)
        local lines = {}
        table.insert(lines, "-------------------------------")
        table.insert(lines, string.format("----- %s -----", event))
        table.insert(lines, string.format("tiktoken: %d", other_count))
        table.insert(lines, "-------------------------------")
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
      end,
    })
  end
end

-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
