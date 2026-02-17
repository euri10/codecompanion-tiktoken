-- plugin/codecompanion-tiktoken.lua
-- Plugin loader and command definitions

-- Define plugin commands
if vim.fn.has("nvim-0.8") == 0 then
  vim.notify("This plugin requires Neovim >= 0.8", vim.log.levels.ERROR)
  return
end


-- Auto-setup for lazy loading
-- Uncomment if needed
-- if vim.fn.has("vim_starting") == 1 then
--   vim.cmd([[autocmd VimEnter * ++once lua require("codecompanion-tiktoken").setup()]])
-- end
