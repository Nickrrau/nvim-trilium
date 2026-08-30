local etapi = require("nvim-trilium.etapi")
local buffer = require("nvim-trilium.buffer")

local function notes_picker(opts)
  opts = opts or {}
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local ancestor = opts.ancestor
  if not ancestor or ancestor == "" then
    ancestor = etapi.workspace_id()
  end
  local notes = etapi.list_subtree(ancestor)

  pickers
    .new(opts, {
      prompt_title = "trilium-notes",
      finder = finders.new_table({
        results = notes,
        entry_maker = function(note)
          return {
            value = note,
            ordinal = note.title .. " " .. note.noteId,
            display = note.title,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          vim.schedule(function()
            if entry and entry.value then
              buffer.open_note(entry.value.noteId)
            end
          end)
        end)
        return true
      end,
    })
    :find()
end

return require("telescope").register_extension({
  exports = {
    ["trilium-notes"] = notes_picker,
  },
})
