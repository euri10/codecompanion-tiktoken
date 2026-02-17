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

## Overview

This repository provides a template for creating Neovim plugins with a standardized structure and best practices. It includes:

- Complete plugin structure with entry points
- Documentation templates
- Test framework setup
- Code quality tools integration
- GitHub workflows for CI/CD
- Community health files

## Features

- 📋 **Complete Structure** - All necessary files and directories for a Neovim plugin
- 📚 **Documentation** - Templates for help docs and README
- 🧪 **Testing** - Plenary-based test setup with minimal configuration
- ✨ **Code Quality** - StyLua and Luacheck configuration
- 🔄 **CI/CD** - GitHub Actions workflows for testing, linting and releases
- 👥 **Community** - Templates for issues, PRs, and contributing guidelines

## Requirements

- Neovim >= 0.8.0
- Git for version control
- (Optional) StyLua for code formatting
- (Optional) Luacheck for static analysis


### Installing the Plugin (For Users)

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "euri10/codecompanion-tiktoken",
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

## Usage

After installation, you can use the plugin with the following commands:

```vim
:PluginNameCommand    " Execute the plugin's main function
:PluginNameToggle     " Toggle the plugin on/off
```

Key mappings (if using which-key):

- `<leader>pf` - Execute the plugin's main function
- `<leader>pt` - Toggle the plugin on/off

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

<div align="center">
  <p>Made with ❤️ by <a href="https://github.com/euri10">euri10</a></p>
</div>
