---@class CodeCompanion.Extension
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.your_extension
local Extension = {}

-- State table to track previous token counts per chat
local prev_token_state = {}

---@class CodeCompanion.TokenContext
---@field system string System prompt content
---@field chat string Chat history content
---@field tools string Tool schemas content
---@field files string Retrieved files content
---@field user string Current user message content
local TokenContext = {}
TokenContext.__index = TokenContext

---Create a new TokenContext from chat data
---@param chat table The chat object with messages and metadata
---@return TokenContext
function TokenContext.new(chat)
  local self = setmetatable({}, TokenContext)

  -- Extract system prompt
  self.system = chat.system_prompt or ""

  -- Extract chat history (all non-system messages)
  local chat_messages = vim.tbl_filter(function(m)
    return m.role ~= "system"
  end, chat.messages or {})
  self.chat = table.concat(
    vim.tbl_map(function(m)
      return m.content or ""
    end, chat_messages),
    "\n"
  )

  -- Extract tool schemas
  self.tools = table.concat(
    vim.tbl_map(function(schema)
      return vim.json.encode(schema)
    end, chat.tool_schemas or {}),
    "\n"
  )

  -- Extract retrieved files
  self.files = table.concat(chat.retrieved_files or {}, "\n")

  -- Extract current user message (last message)
  local last_message = chat.messages and chat.messages[#chat.messages]
  self.user = last_message and last_message.content or ""

  return self
end

---Setup the extension
---@param opts table Configuration options
function Extension.setup(opts)
  -- Initialize extension
  -- Add actions, keymaps etc.
  local tiktoken = require("tiktoken")
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

        -- Build tagged context sections
        local context = TokenContext.new(chat)
        local context_sections = {
          system = context.system,
          chat = context.chat,
          tools = context.tools,
          files = context.files,
          user = context.user,
        }

        local token_breakdown = {}
        local total_tokens = 0
        for section_name, text in pairs(context_sections) do
          local count = tiktoken.count_text(text, model_name)
          token_breakdown[section_name] = count
          total_tokens = total_tokens + count
        end

        -- Delta tracking: use chat.id if available, else fallback to bufnr
        local chat_id = chat.id or (args.data and args.data.bufnr) or 0
        local prev = prev_token_state[chat_id] or { breakdown = {}, total = 0 }
        local delta_breakdown = {}
        for name, count in pairs(token_breakdown) do
          local prev_count = prev.breakdown[name] or 0
          delta_breakdown[name] = count - prev_count
        end
        local total_delta = total_tokens - (prev.total or 0)
        prev_token_state[chat_id] = { breakdown = vim.deepcopy(token_breakdown), total = total_tokens }

        -- Notify UI only (no floating window)
        local lines = { "Token Intelligence" }
        table.insert(lines, "-------------------------------")
        for name, count in pairs(token_breakdown) do
          local delta = delta_breakdown[name]
          local delta_str = delta ~= 0 and string.format(" (%d)", delta) or ""
          table.insert(lines, string.format("• %s: %d%s", name, count, delta_str))
        end
        table.insert(lines, "-------------------------------")
        table.insert(lines, string.format("Total: %d (%d)", total_tokens, total_delta))

        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
      end,
    })
  end
end

-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
