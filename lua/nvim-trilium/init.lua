local config = require("nvim-trilium.config")
local buffer = require("nvim-trilium.buffer")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

function M.save()
  buffer.save()
end

function M.open(note_id)
  buffer.open_note(note_id)
end

function M.list(parent_id)
  buffer.browse(parent_id)
end

return M
