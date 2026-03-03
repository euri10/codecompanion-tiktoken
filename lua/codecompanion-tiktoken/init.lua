-- codecompanion-tiktoken/init.lua
-- Main entry point for your plugin

-- Plugin configuration
local config = {
  -- Default configuration options
  enabled = true,
  debug = false,
  -- Add your plugin's configuration options here
}

-- Main plugin module
local M = {}

---Setup function - called by user to configure the plugin
---@param opts table: User configuration options
M.setup = function(opts)
  -- Merge user configuration with defaults
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- Validate configuration
  if type(config.enabled) ~= "boolean" then
    vim.notify("codecompanion-tiktoken: 'enabled' option must be boolean", vim.log.levels.ERROR)
    return
  end

  -- Add additional validations as needed
  -- TODO: validate default_model against a list of supported models
  -- they might come from codeompanion models ?

  -- Early return if disabled
  if not config.enabled then
    vim.notify("codecompanion-tiktoken is disabled", vim.log.levels.INFO)
    return
  end

  -- Set up autocommands if necessary
  local tiktoken = require("tiktoken")

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionToolApprovalRequested",
    callback = function(args)
      vim.notify(vim.inspect(args), vim.log.levels.DEBUG, { title = "CodeCompanion Tool Approval" })
      local chat = require("codecompanion").buf_get_chat(args.data.bufnr)

      chat:add_callback("on_before_submit", function(c, info)
        if not c or not c.messages then
          vim.notify(
            "Error: Chat or messages not found in callback data",
            vim.log.levels.ERROR,
            { title = "CodeCompanion" }
          )
          return
        end

        local model_name = info.adapter.model.name
        -- Example: Extract sections (adapt as needed for your data structures)
        local system_prompt = c.system_prompt or ""
        local chat_history = table.concat(vim.tbl_map(function(m)
          return (m.role ~= "system" and m.content) or ""
        end, c.messages), "\n")
        local tool_schemas = c.tool_schemas or ""
        local retrieved_files = c.retrieved_files or ""
        local user_message = c.messages[#c.messages] and c.messages[#c.messages].content or ""

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

        -- Format breakdown for display
        local lines = { "Context Breakdown:" }
        for name, count in pairs(token_breakdown) do
          table.insert(lines, string.format("• %s: %d tokens", name, count))
        end
        table.insert(lines, "-------------------------------")
        table.insert(lines, string.format("Total: %d tokens", total_tokens))

        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Token Breakdown" })
      end)
    end,
  })

  -- Load keymappings if necessary
  M.setup_keymaps()

  -- Log debug information
  if config.debug then
    vim.notify("codecompanion-tiktoken: plugin initialized with config: " .. vim.inspect(config), vim.log.levels.DEBUG)
  end
end

---Set up keymaps for the plugin
M.setup_keymaps = function()
  -- Example keymap setup
  local opts = { noremap = true, silent = true } -- Used for keymap functions

  -- Example of setting a keymap
  -- vim.keymap.set("n", "<leader>p", function() require("codecompanion-tiktoken").some_function() end, opts)

  -- Register with which-key if available
  local ok, wk = pcall(require, "which-key")
  -- if ok then
  --   wk.register({
  --     ["<leader>p"] = {
  --       name = "+codecompanion-tiktoken",
  --       f = {
  --         function()
  --           M.some_function()
  --         end,
  --         "Plugin Function",
  --       },
  --       t = {
  --         function()
  --           M.toggle()
  --         end,
  --         "Toggle Plugin",
  --       },
  --     },
  --   })
  -- end
end

---Example function that your plugin provides
M.some_function = function()
  -- Your plugin logic here
  vim.notify("codecompanion-tiktoken: some_function called", vim.log.levels.INFO)
end

---Toggle plugin enabled state
M.toggle = function()
  config.enabled = not config.enabled
  vim.notify("codecompanion-tiktoken: " .. (config.enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

---Get current configuration
---@return table: Current configuration
M.get_config = function()
  return config
end

return M
