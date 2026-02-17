local data_dir = vim.fn.stdpath("data") .. "/site/pack/vendor/start"
local plenary_dir = data_dir .. "/plenary.nvim"

if vim.fn.empty(vim.fn.glob(plenary_dir)) > 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_dir,
  })
end

vim.opt.runtimepath:prepend(plenary_dir)

-- minimal-init.lua
-- Minimal configuration for testing

-- Set up package path
local package_path = vim.fn.stdpath("config") .. "/lua"
package.path = package.path .. ";" .. package_path .. "/?.lua;" .. package_path .. "/?/init.lua"

-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Basic options
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.timeoutlen = 300
vim.opt.updatetime = 100
vim.opt.compatible = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.undofile = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.showmode = false

-- Basic plugin loading code
local function load_plugin(codecompanion_tiktoken)
  -- Get the plugin path
  local plugin_path = debug.getinfo(2, "S").source:sub(2):match("(.*/tests)/.*$") .. "/.."

  -- Add the plugin to the runtimepath
  vim.opt.runtimepath:append(plugin_path)

  -- Attempt to load the plugin
  local status_ok, plugin = pcall(require, codecompanion_tiktoken)
  if not status_ok then
    vim.notify("Failed to load " .. codecompanion_tiktoken, vim.log.levels.ERROR)
    return nil
  end

  -- Return the loaded plugin
  return plugin
end

-- Setup the plugin
local codecompanion_tiktoken = "codecompanion-tiktoken" -- Replace with your actual plugin name
local plugin = load_plugin(codecompanion_tiktoken)

if plugin then
  plugin.setup({
    -- Test configuration
    enabled = true,
    debug = true,
  })
  vim.notify(codecompanion_tiktoken .. " loaded successfully", vim.log.levels.INFO)
else
  vim.notify("Could not load " .. codecompanion_tiktoken, vim.log.levels.ERROR)
end

-- Return the loaded plugin for direct access in tests
return plugin
