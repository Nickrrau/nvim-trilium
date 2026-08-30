if vim.g.loaded_nvim_trilium then
  return
end
vim.g.loaded_nvim_trilium = true

local function t()
  return require("nvim-trilium")
end

vim.api.nvim_create_user_command("TriliumOpen", function(opts)
  t().open(opts.args)
end, { nargs = "?", desc = "Open a Trilium note by id or title; create if missing" })

vim.api.nvim_create_user_command("TriliumSave", function()
  t().save()
end, { desc = "Save the current Trilium note buffer" })

vim.api.nvim_create_user_command("TriliumList", function(opts)
  t().list(opts.args)
end, { nargs = "?", desc = "Browse notes like a directory listing" })
