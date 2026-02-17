<div align="center">

# codecompanion-tiktoken

[![GitHub License](https://img.shields.io/github/license/euri10/codecompanion-tiktoken?style=flat-square)](https://github.com/euri10/codecompanion-tiktoken/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/euri10/codecompanion-tiktoken?style=flat-square)](https://github.com/euri10/codecompanion-tiktoken/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/euri10/codecompanion-tiktoken?style=flat-square)](https://github.com/euri10/codecompanion-tiktoken/issues)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/euri10/codecompanion-tiktoken?style=flat-square)](https://github.com/euri10/codecompanion-tiktoken/commits/main)
[![Neovim Version](https://img.shields.io/badge/Neovim-0.8%2B-blueviolet?style=flat-square&logo=neovim)](https://github.com/neovim/neovim)
[![CI](https://img.shields.io/github/actions/workflow/status/euri10/codecompanion-tiktoken/ci.yml?branch=main&style=flat-square&logo=github)](https://github.com/euri10/codecompanion-tiktoken/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/Version-0.1.1-blue?style=flat-square)](https://github.com/euri10/codecompanion-tiktoken/releases/tag/v0.1.1)
[![Discussions](https://img.shields.io/github/discussions/euri10/codecompanion-tiktoken?style=flat-square&logo=github)](https://github.com/euri10/codecompanion-tiktoken/discussions)

*allows codecompanion to count tokens using the tiktoken-rs library*

[Features](#features) •
[Requirements](#requirements) •
[Installation](#installation) •
[Usage](#usage) •
[Configuration](#configuration) •
[Development](#development) •
[Contributing](#contributing) •
[License](#license) •
[Discussions](https://github.com/euri10/codecompanion-tiktoken/discussions)

</div>

### Installing the Plugin (For Users)

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "euri10/codecompanion-tiktoken",
  build = "make build"
  dependencies = {
    -- Add dependencies here
  },
  config = function()
    require("codecompanion-tiktoken").setup({
      -- Your configuration
    })
  end
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'euri10/codecompanion-tiktoken',
  requires = {
    -- Add dependencies here
  },
  config = function()
    require('codecompanion-tiktoken').setup({
      -- Your configuration
    })
  end
}
```

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'euri10/codecompanion-tiktoken'

" In your init.vim after plug#end():
lua require('codecompanion-tiktoken').setup({})
```

## Use as a codecompanion extension

```lua
extensions = {
  token_counter = {
    enabled = true,
    opts = {},
    callback = {
      setup = function(ext_config)
        -- Define a new action for chat keymaps
        local count_tokens_action = {
          modes = {
            n = "gtt", -- Normal mode keymap: gtt = "get count tokens"
          },
          description = "Count Tokens",
          callback = function(chat)
            -- Make sure tiktoken is loaded
            local ok, tiktoken = pcall(require, "tiktoken")
            if not ok then
              vim.notify("tiktoken module not found", vim.log.levels.ERROR)
              return
            end

            if not chat or not chat.messages then
              vim.notify("Chat messages not found", vim.log.levels.ERROR)
              return
            end

            -- Pick model dynamically
            local model_name = "GPT-4o"
            if chat.adapter and chat.adapter.model and chat.adapter.model.name then
              model_name = chat.adapter.model.name
            end

            -- Count total messages tokens
            local total_tokens = tiktoken.count_messages(chat.messages, model_name)
    local total_text = 0

            -- Count total text in first message (optional)
    for i, msg in ipairs(chat.messages) do
      local text_tokens = tiktoken.count_text(msg.content, model_name)
      vim.notify(
        string.format("Message %d tokens: %d", i, text_tokens),
        vim.log.levels.INFO,
        { title = "Token Counter" }
      )
      total_text = total_text + text_tokens
    end

            vim.notify(
              string.format("[%s] Total tokens: %d, all message tokens: %d", model_name, total_tokens,total_text),
              vim.log.levels.INFO,
              { title = "Token Counter" }
            )
          end,
        }

        -- Add the action to CodeCompanion chat keymaps
        local chat_keymaps = require("codecompanion.config").interactions.chat.keymaps
        chat_keymaps.count_tokens = count_tokens_action
      end,

      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatCreated",
        callback = function(args)
          local chat = require("codecompanion").buf_get_chat(args.data.bufnr)

          chat:add_callback("on_before_submit", function(c, info)
            if not c or not c.messages then
              vim.notify("Error: Chat or messages not found in callback data", vim.log.levels.ERROR, { title = "CodeCompanion" })
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
      }),
      -- Optional: Export functions for other extensions or scripts
      exports = {
        get_tokens = function(chat)
          local model_name = "GPT-4o"
          if chat.adapter and chat.adapter.model and chat.adapter.model.name then
            model_name = chat.adapter.model.name
          end
          return tiktoken.count_messages(chat.messages, model_name)
        end,
      },
    },
  },
},
```
## Configuration

Default configuration:

```lua
require("codecompanion-tiktoken").setup({
  enabled = true,
  debug = false,
  -- Add other options here
})
```

| Option    | Type      | Default | Description           |
| --------- | --------- | ------- | --------------------- |
| `enabled` | `boolean` | `true`  | Enable/disable plugin |
| `debug`   | `boolean` | `false` | Enable debug logging  |

## Development

### Setting Up Development Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/euri10/codecompanion-tiktoken.git
   cd codecompanion-tiktoken
   ```

2. Install development dependencies:
   - Neovim 0.8+
   - Luacheck for linting
   - StyLua for formatting

3. Set up pre-commit hooks (important first step!):
   ```bash
   ./scripts/setup-hooks.sh
   ```
   This will enable automatic formatting, linting, and testing before each commit. Make sure to run this before making any changes to ensure code quality.

### Directory Structure

```
.
├── lua/
│   └── codecompanion-tiktoken/      # Plugin code
│       └── init.lua      # Main entry point
├── plugin/
│   └── codecompanion-tiktoken.lua   # Plugin load script
├── doc/
│   └── codecompanion-tiktoken.txt   # Help documentation
├── tests/
│   ├── minimal-init.lua  # Minimal config for testing
│   └── spec/             # Test specifications
│       └── plugin_spec.lua
├── .github/              # GitHub specific files
├── .githooks/            # Git hooks for development
├── scripts/              # Development scripts
├── .stylua.toml          # StyLua configuration
├── .luacheckrc           # Luacheck configuration
└── README.md             # This file
```

### Testing

Before making changes, ensure your development environment is set up with pre-commit hooks:
```bash
./scripts/setup-hooks.sh
```

Run tests with:

```bash
make test
```

Or manually:

```bash
nvim --headless -u tests/minimal-init.lua -c "lua require('plenary.test_harness').test_directory('tests/spec')"
```

### Code Quality

Format code with StyLua:

```bash
stylua .
```

Lint code with Luacheck:

```bash
luacheck .
```

Both tools are integrated with the pre-commit hooks when using [hooks-util](https://github.com/euri10/hooks-util).

## Contributing

Contributions are welcome! Here's how to contribute to this template:

1. Fork the repository
2. Create a feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request

Please make sure to:
- Follow the coding style (run StyLua)
- Add tests for new features
- Update documentation as needed

## License

This template is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Neovim](https://neovim.io/) - The core editor
- [lazy.nvim](https://github.com/folke/lazy.nvim) - Plugin manager
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - Testing framework
- [StyLua](https://github.com/JohnnyMorganz/StyLua) - Lua formatter
- [Luacheck](https://github.com/lunarmodules/luacheck) - Lua linter
- [hooks-util](https://github.com/euri10/hooks-util) - Git hooks framework

## Discussions

Have questions or ideas? Join the conversation in [GitHub Discussions](https://github.com/euri10/codecompanion-tiktoken/discussions).

- **Questions**: For help with using or developing the plugin
- **Ideas**: Suggest new features or improvements
- **Show and Tell**: Share how you're using this plugin
- **General**: For any other topics related to this plugin

---
