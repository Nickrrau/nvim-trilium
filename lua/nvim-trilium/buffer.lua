local etapi = require("nvim-trilium.etapi")
local config = require("nvim-trilium.config")

local M = {}

local browse_buf

local function lines_of(text)
  if text == "" then
    return { "" }
  end
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function set_note_name(buf, note)
  vim.b[buf].trilium_note_id = note.noteId
  vim.b[buf].trilium_title = note.title
  vim.b[buf].trilium_type = note.type
  pcall(vim.api.nvim_buf_set_name, buf, "trilium://" .. note.noteId .. "/" .. note.title:gsub("[/\\]", "_"))
end

local function is_dir(note)
  return note.childNoteIds and #note.childNoteIds > 0
end

function M.save(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local note_id = vim.b[buf].trilium_note_id
  if not note_id then
    error("nvim-trilium: buffer is not a note", 0)
  end
  etapi.put_content(note_id, buffer_text(buf))
  vim.bo[buf].modified = false
  vim.notify("nvim-trilium: saved " .. note_id, vim.log.levels.INFO)
end

function M.open_note(note_id)
  local note, created = etapi.resolve_or_create(note_id)
  local content = ""
  if not created then
    content = etapi.get_content(note.noteId)
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(content))
  set_note_name(buf, note)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modified = false
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.save(buf)
    end,
  })
  if created then
    vim.notify("nvim-trilium: created " .. note.noteId .. " (" .. note.title .. ")", vim.log.levels.INFO)
  end
  return buf
end

local function entry_at_cursor(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local entries = vim.b[buf].trilium_entries or {}
  return entries[tostring(row)]
end

local function render_browse(buf, note)
  local kids = etapi.children(note.noteId)
  local lines = {}
  local entries = {}

  if note.noteId ~= "root" and note.parentNoteIds and note.parentNoteIds[1] then
    table.insert(lines, "../")
    entries["1"] = { kind = "up", note_id = note.parentNoteIds[1] }
  end

  for _, child in ipairs(kids) do
    local dir = is_dir(child)
    table.insert(lines, dir and (child.title .. "/") or child.title)
    entries[tostring(#lines)] = {
      kind = dir and "dir" or "file",
      note_id = child.noteId,
    }
  end

  if #lines == 0 then
    table.insert(lines, "(empty)")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.b[buf].trilium_browse_id = note.noteId
  vim.b[buf].trilium_entries = entries
  pcall(vim.api.nvim_buf_set_name, buf, "trilium:///" .. note.noteId)
end

function M.browse(parent_id)
  parent_id = (parent_id and parent_id ~= "") and parent_id or etapi.workspace_id()
  local note = etapi.get_note(parent_id)

  if not browse_buf or not vim.api.nvim_buf_is_valid(browse_buf) then
    browse_buf = vim.api.nvim_create_buf(true, true)
    vim.bo[browse_buf].buftype = "nofile"
    vim.bo[browse_buf].bufhidden = "hide"
    vim.bo[browse_buf].swapfile = false
    vim.bo[browse_buf].filetype = "trilium"
    vim.b[browse_buf].trilium_browser = true

    local function map(lhs, fn)
      vim.keymap.set("n", lhs, fn, { buffer = browse_buf, silent = true, nowait = true })
    end

    map("<CR>", function()
      local e = entry_at_cursor(browse_buf)
      if not e then
        return
      end
      if e.kind == "up" or e.kind == "dir" then
        M.browse(e.note_id)
      else
        M.open_note(e.note_id)
      end
    end)
    map("-", function()
      local id = vim.b[browse_buf].trilium_browse_id
      local n = etapi.get_note(id)
      local parent = n.parentNoteIds and n.parentNoteIds[1]
      if parent then
        M.browse(parent)
      end
    end)
    map("o", function()
      local e = entry_at_cursor(browse_buf)
      if e and e.note_id and e.kind ~= "up" then
        M.open_note(e.note_id)
      end
    end)
    map("q", function()
      vim.api.nvim_buf_delete(browse_buf, { force = true })
    end)
    map("r", function()
      M.browse(vim.b[browse_buf].trilium_browse_id)
    end)
  end

  vim.api.nvim_set_current_buf(browse_buf)
  render_browse(browse_buf, note)
  return browse_buf
end

return M
