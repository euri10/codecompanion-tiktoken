---@class CodeCompanion.Extension
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.your_extension
local Extension = {}

-- State table to track previous token counts per chat
local prev_token_state = {}


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
        if not chat or not chat.messages then
          vim.notify("Token breakdown: chat or messages not found", vim.log.levels.WARN)
          return
        end

        local model_name = chat.adapter and chat.adapter.model and chat.adapter.model.name or "unknown"
        local system_prompt = chat.system_prompt or ""
        local chat_history = table.concat(
          vim.tbl_map(function(m)
            return (m.role ~= "system" and m.content) or ""
          end, chat.messages),
          "\n"
        )
        local tool_schemas = chat.tool_schemas or ""
        local retrieved_files = chat.retrieved_files or ""
        local user_message = chat.messages[#chat.messages] and chat.messages[#chat.messages].content or ""

        local context_sections = {
          ["System prompt"] = system_prompt,
          ["Chat history"] = chat_history,
          ["Tool schemas"] = tool_schemas,
          ["Retrieved files"] = retrieved_files,
          ["Current message"] = user_message,
        }

        local token_breakdown = {}
        local total_tokens = 0
        for name, text in pairs(context_sections) do
          local count = tiktoken.count_text(text, model_name)
          token_breakdown[name] = count
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
          local delta_str = delta ~= 0 and string.format(" (%+d)", delta) or ""
          table.insert(lines, string.format("• %s: %d%s", name, count, delta_str))
        end
        table.insert(lines, "-------------------------------")
        table.insert(lines, string.format("Total: %d (%+d)", total_tokens, total_delta))

        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })


      end,
    })
  end
end
-- Optional: Functions exposed via codecompanion.extensions.your_extension
-- Extension.exports = {
--   clear_history = function() end
-- }

return Extension
--
--   -- Load keymappings if necessary
--   M.setup_keymaps()
--
--   -- Log debug information
--   if config.debug then
--     vim.notify("codecompanion-tiktoken: plugin initialized with config: " .. vim.inspect(config), vim.log.levels.DEBUG)
--   end
-- end
--
-- ---Set up keymaps for the plugin
-- M.setup_keymaps = function()
--   -- Example keymap setup
--   local opts = { noremap = true, silent = true } -- Used for keymap functions
--
--   -- Example of setting a keymap
--   -- vim.keymap.set("n", "<leader>p", function() require("codecompanion-tiktoken").some_function() end, opts)
--
--   -- Register with which-key if available
--   local ok, wk = pcall(require, "which-key")
--   -- if ok then
--   --   wk.register({
--   --     ["<leader>p"] = {
--   --       name = "+codecompanion-tiktoken",
--   --       f = {
--   --         function()
--   --           M.some_function()
--   --         end,
--   --         "Plugin Function",
--   --       },
--   --       t = {
--   --         function()
--   --           M.toggle()
--   --         end,
--   --         "Toggle Plugin",
--   --       },
--   --     },
--   --   })
--   -- end
-- end
--
-- ---Example function that your plugin provides
-- M.some_function = function()
--   -- Your plugin logic here
--   vim.notify("codecompanion-tiktoken: some_function called", vim.log.levels.INFO)
-- end
--
-- ---Toggle plugin enabled state
-- M.toggle = function()
--   config.enabled = not config.enabled
--   vim.notify("codecompanion-tiktoken: " .. (config.enabled and "enabled" or "disabled"), vim.log.levels.INFO)
-- end
--
-- ---Get current configuration
-- ---@return table: Current configuration
-- M.get_config = function()
--   return config
-- end
--
-- return M
