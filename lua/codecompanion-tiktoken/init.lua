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
    pattern = "CodeCompanionChatCreated",
    callback = function(args)
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

        local total_tokens = tiktoken.count_messages(c.messages, info.adapter.model.name)
        local total_text = tiktoken.count_text(c.messages[1].content, info.adapter.model.name)

        vim.notify(
          string.format(
            "Using tiktoken-rs with %s.\nAccurate total tokens: %d\nAccurate total text: %d",
            info.adapter.model.name,
            total_tokens,
            total_text
          ),
          vim.log.levels.INFO,
          { title = "CodeCompanion" }
        )
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
  if ok then
    wk.register({
      ["<leader>p"] = {
        name = "+codecompanion-tiktoken",
        f = {
          function()
            M.some_function()
          end,
          "Plugin Function",
        },
        t = {
          function()
            M.toggle()
          end,
          "Toggle Plugin",
        },
      },
    })
  end
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
