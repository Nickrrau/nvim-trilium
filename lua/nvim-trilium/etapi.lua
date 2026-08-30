local config = require("nvim-trilium.config")

local M = {}

local function curl_bin()
  if vim.fn.executable("curl") ~= 1 then
    error("nvim-trilium: curl is required on PATH", 0)
  end
  return "curl"
end

local function run_curl(args, stdin)
  local cmd = { curl_bin() }
  vim.list_extend(cmd, args)

  if vim.system then
    local opts = { text = true }
    if stdin then
      opts.stdin = stdin
    end
    local r = vim.system(cmd, opts):wait()
    if r.signal and r.signal ~= 0 then
      error("nvim-trilium: curl killed by signal " .. tostring(r.signal), 0)
    end
    return r.stdout or "", r.stderr or "", r.code
  end

  local tmp
  if stdin then
    tmp = vim.fn.tempname()
    vim.fn.writefile(vim.split(stdin, "\n", { plain = true }), tmp, "b")
    table.insert(cmd, "--data-binary")
    table.insert(cmd, "@" .. tmp)
  end
  local out = vim.fn.system(cmd)
  local code = vim.v.shell_error
  if tmp then
    vim.fn.delete(tmp)
  end
  return out, "", code
end

local function request(method, path, opts)
  opts = opts or {}
  local cfg = config.require_token()
  local url = cfg.url .. "/etapi" .. path
  local args = {
    "-sS",
    "-w",
    "\n%{http_code}",
    "-X",
    method,
    "-H",
    "Authorization: " .. cfg.token,
  }
  if opts.json then
    table.insert(args, "-H")
    table.insert(args, "Content-Type: application/json")
  elseif opts.plain then
    table.insert(args, "-H")
    table.insert(args, "Content-Type: text/plain")
  end
  if opts.query then
    local parts = {}
    for k, v in pairs(opts.query) do
      table.insert(parts, vim.uri_encode(tostring(k)) .. "=" .. vim.uri_encode(tostring(v)))
    end
    table.sort(parts)
    url = url .. "?" .. table.concat(parts, "&")
  end
  table.insert(args, url)

  local body
  if opts.json then
    body = vim.json.encode(opts.json)
    table.insert(args, "--data-binary")
    table.insert(args, "@-")
  elseif opts.plain then
    body = opts.plain
    table.insert(args, "--data-binary")
    table.insert(args, "@-")
  end

  local stdout, stderr, code = run_curl(args, body)
  if code ~= 0 then
    error(("nvim-trilium: curl failed (%d): %s"):format(code, (stderr ~= "" and stderr or stdout)), 0)
  end

  local http = stdout:match("\n(%d%d%d)%s*$")
  local payload = stdout:gsub("\n%d%d%d%s*$", "")
  http = tonumber(http)
  if not http then
    error("nvim-trilium: could not parse HTTP status from curl", 0)
  end
  if http < 200 or http >= 300 then
    local msg = payload
    local ok, decoded = pcall(vim.json.decode, payload)
    if ok and type(decoded) == "table" and decoded.message then
      msg = decoded.message
    end
    error(("nvim-trilium: ETAPI %s %s -> %d: %s"):format(method, path, http, msg), 0)
  end
  return http, payload
end

function M.app_info()
  local _, payload = request("GET", "/app-info")
  return vim.json.decode(payload)
end

function M.search(query, extra)
  extra = extra or {}
  local q = {
    search = query,
    limit = extra.limit or config.get().search_limit,
    orderBy = extra.order_by or "title",
  }
  if extra.ancestor then
    q.ancestorNoteId = extra.ancestor
  end
  if extra.ancestor_depth then
    q.ancestorDepth = extra.ancestor_depth
  end
  if extra.fast ~= nil then
    q.fastSearch = extra.fast and "true" or "false"
  end
  local _, payload = request("GET", "/notes", { query = q })
  return vim.json.decode(payload)
end

function M.get_note(note_id)
  local _, payload = request("GET", "/notes/" .. note_id)
  return vim.json.decode(payload)
end

function M.try_get_note(note_id)
  local ok, note = pcall(M.get_note, note_id)
  if ok and type(note) == "table" and note.noteId then
    return note
  end
end

function M.child_by_title(parent_id, title)
  for _, n in ipairs(M.children(parent_id)) do
    if n.title == title then
      return n
    end
  end
end

function M.find_by_title(title)
  local q = "note.title = '" .. title:gsub("'", "\\'") .. "'"
  local res = M.search(q, { limit = 20, order_by = "title" })
  for _, n in ipairs(res.results or {}) do
    if n.title == title then
      return n
    end
  end
end

local function ensure_child(parent_id, title)
  local existing = M.child_by_title(parent_id, title)
  if existing then
    return existing, false
  end
  local created = M.create_note({
    parent_note_id = parent_id,
    title = title,
    content = "",
  })
  return created.note, true
end

function M.workspace_id()
  local spec = config.parent_spec()
  local by_id = M.try_get_note(spec)
  if by_id then
    return by_id.noteId
  end
  local child = M.child_by_title("root", spec)
  if child then
    return child.noteId
  end
  return M.create_note({
    parent_note_id = "root",
    title = spec,
    content = "",
  }).note.noteId
end

function M.resolve_or_create(query)
  query = query or ""
  local parts = vim.split(query:gsub("\\", "/"), "/", { trimempty = true })
  local parent_id = M.workspace_id()

  if #parts <= 1 then
    local name = parts[1]
    if name then
      local by_id = M.try_get_note(name)
      if by_id then
        return by_id, false
      end
      local local_child = M.child_by_title(parent_id, name)
      if local_child then
        return local_child, false
      end
    end
    local title = name or "untitled"
    local created = M.create_note({
      parent_note_id = parent_id,
      title = title,
      content = "",
    })
    return created.note, true
  end

  local created_any = false
  for i = 1, #parts - 1 do
    local folder, created
    if i == 1 then
      folder = M.child_by_title(parent_id, parts[i]) or M.try_get_note(parts[i])
      if not folder then
        folder, created = ensure_child(parent_id, parts[i])
      end
    else
      folder, created = ensure_child(parent_id, parts[i])
    end
    created_any = created_any or created
    parent_id = folder.noteId
  end
  local note, created = ensure_child(parent_id, parts[#parts])
  return note, created_any or created
end

function M.get_content(note_id)
  local _, payload = request("GET", "/notes/" .. note_id .. "/content")
  return payload
end

function M.put_content(note_id, content)
  request("PUT", "/notes/" .. note_id .. "/content", { plain = content })
end

function M.patch_note(note_id, fields)
  local _, payload = request("PATCH", "/notes/" .. note_id, { json = fields })
  return vim.json.decode(payload)
end

function M.create_note(opts)
  local cfg = config.get()
  local body = {
    parentNoteId = opts.parent_note_id or M.workspace_id(),
    title = opts.title,
    type = opts.type or cfg.note_type,
    content = opts.content or "",
  }
  local _, payload = request("POST", "/create-note", { json = body })
  return vim.json.decode(payload)
end

function M.children(note_id)
  local res = M.search("note.title %= '.*'", {
    ancestor = note_id,
    ancestor_depth = "eq1",
    limit = 200,
    order_by = "title",
  })
  local kids = {}
  for _, n in ipairs(res.results or {}) do
    if n.noteId ~= note_id and not n.noteId:match("^_") then
      table.insert(kids, n)
    end
  end
  return kids
end

return M
