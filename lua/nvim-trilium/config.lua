local M = {}

M.defaults = {
  url = "http://127.0.0.1:37840",
  token = nil,
  -- Title or note id. Created under Trilium `root` if missing.
  parent = "nvim-notes",
  note_type = "text",
  search_limit = 50,
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  if opts.parent_note_id and not opts.parent then
    M.values.parent = opts.parent_note_id
  end
  if not M.values.token or M.values.token == "" then
    M.values.token = vim.env.TRILIUM_ETAPI_TOKEN
  end
  if vim.env.TRILIUM_URL and vim.env.TRILIUM_URL ~= "" then
    M.values.url = vim.env.TRILIUM_URL
  end
  M.values.url = (M.values.url or ""):gsub("/+$", "")
end

function M.get()
  return M.values
end

function M.parent_spec()
  return M.values.parent or "nvim-notes"
end

function M.require_token()
  local cfg = M.get()
  if not cfg.token or cfg.token == "" then
    error("nvim-trilium: set token in setup() or TRILIUM_ETAPI_TOKEN", 0)
  end
  return cfg
end

return M
