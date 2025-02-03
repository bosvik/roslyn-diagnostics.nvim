---@param lines string[]?
---@param lnum integer
---@param col integer
---@param offset_encoding string
---@return integer
local function line_byte_from_position(lines, lnum, col, offset_encoding)
  if not lines or offset_encoding == "utf-8" then return col end

  local line = lines[lnum + 1]
  local ok, result = pcall(vim.str_byteindex, line, col, offset_encoding == "utf-16")
  if ok then
    return result --- @type integer
  end

  return col
end

---@param severity lsp.DiagnosticSeverity
local function severity_lsp_to_vim(severity)
  if type(severity) == "string" then
    severity = vim.lsp.protocol.DiagnosticSeverity[severity] --- @type integer
  end
  return severity
end

---@param uri unknown
---@param buf_lines string[]?
---@return lsp.DidOpenTextDocumentParams?
local function create_textdocument(uri, buf_lines)
  if not buf_lines then return end
  local params = {
    textDocument = {
      uri = uri,
      version = 0,
      text = vim.fn.join(buf_lines, "\n"),
      languageId = "csharp",
    },
  }
  return params
end

--- @param diagnostic lsp.Diagnostic
--- @param client_id integer
--- @return table?
local function tags_lsp_to_vim(diagnostic, client_id)
  local tags ---@type table?
  for _, tag in ipairs(diagnostic.tags or {}) do
    if tag == vim.lsp.protocol.DiagnosticTag.Unnecessary then
      tags = tags or {}
      tags.unnecessary = true
    elseif tag == vim.lsp.protocol.DiagnosticTag.Deprecated then
      tags = tags or {}
      tags.deprecated = true
    else
      vim.lsp.log.info(string.format("Unknown DiagnosticTag %d from LSP client %d", tag, client_id))
    end
  end
  return tags
end

---@param bufnr integer
---@return string[]?
local function get_buf_lines(bufnr)
  if vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return lines
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  local f = io.open(filename)
  if not f then return end

  local content = f:read("*a")
  if not content then
    f:close()
    return
  end

  local lines = vim.split(content, "\n")
  f:close()
  return lines
end

---@param diagnostics lsp.Diagnostic[]
---@param bufnr integer
---@param client_id integer
---@return vim.Diagnostic[]
local function diagnostic_lsp_to_vim(diagnostics, uri, bufnr, client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  local buf_lines = get_buf_lines(bufnr)
  local params = create_textdocument(uri, buf_lines)
  if params and client then
    client.notify("textDocument/didOpen", params)
    client.notify("textDocument/didClose", params)
  end

  local offset_encoding = client and client.offset_encoding or "utf-16"
  --- @param diagnostic lsp.Diagnostic
  --- @return vim.Diagnostic
  return vim.tbl_map(function(diagnostic)
    local start = diagnostic.range.start
    local _end = diagnostic.range["end"]
    local message = diagnostic.message
    if type(message) ~= "string" then
      vim.notify_once(string.format("Unsupported Markup message from LSP client %d", client_id), 4)
      message = diagnostic.message.value
    end
    --- @type vim.Diagnostic
    return {
      lnum = start.line,
      col = line_byte_from_position(buf_lines, start.line, start.character, offset_encoding),
      end_lnum = _end.line,
      end_col = line_byte_from_position(buf_lines, _end.line, _end.character, offset_encoding),
      severity = severity_lsp_to_vim(diagnostic.severity),
      message = message,
      source = diagnostic.source,
      code = diagnostic.code,
      _tags = tags_lsp_to_vim(diagnostic, client_id),
      user_data = {
        lsp = diagnostic,
      },
    }
  end, diagnostics)
end

local function close_unlisted_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.bo[buf].buflisted then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
end

local function unload_unlisted_buffers(buf)
  if not vim.bo[buf].buflisted then vim.api.nvim_buf_delete(buf, { unload = true }) end
end

local function find_buf_or_make_unlisted(filename)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == filename then return buf end
  end

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, filename)
  unload_unlisted_buffers(buf)
  return buf
end

local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("RequestDiagnostics", function() M.request_diagnostics() end, {})
  vim.api.nvim_create_autocmd({ "LspAttach", "InsertLeave" }, {
    group = vim.api.nvim_create_augroup("roslyn_diagnostics", { clear = true }),
    pattern = "*.cs",
    callback = function()
      vim.defer_fn(function()
        local clients = vim.lsp.get_clients({ name = "roslyn" })
        if not clients or #clients == 0 then return end

        local buffers = vim.lsp.get_buffers_by_client_id(clients[1].id)
        for _, buf in ipairs(buffers) do
          vim.diagnostic.reset(nil, buf)
          vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
          vim.lsp.codelens.refresh()
        end
      end, 100)
    end,
  })
end

M.request_diagnostics = function()
  close_unlisted_buffers()
  local spinner = require("roslyn-diagnostics.spinner").new()
  local clients = vim.lsp.get_clients({ name = "roslyn" })
  if not clients or #clients == 0 then
    vim.notify("Roslyn has not attached to the buffer yet. Try again.")
    return
  end
  local client = clients[1]
  if client.name == "roslyn" then
    spinner:start_spinner("Populating workspace diagnostics")
    vim.diagnostic.reset()
    client.request("workspace/diagnostic", { previousResultIds = {} }, function(err, result, context, config)
      local ns = vim.lsp.diagnostic.get_namespace(client.id)

      for _, per_file_diags in ipairs(result.items) do
        local filename = string.gsub(per_file_diags.uri, "file://", "")
        if string.find(filename, "%.cs$") and not string.find(filename, "/obj/") and not string.find(filename, "/bin/") then
          if per_file_diags.items ~= nil and #per_file_diags.items > 0 then
            local buf = find_buf_or_make_unlisted(filename)

            local diagnostics = diagnostic_lsp_to_vim(per_file_diags.items, per_file_diags.uri, buf, context.client_id)
            vim.diagnostic.set(ns, buf, diagnostics)
            vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
          end
        end
      end
      spinner:stop_spinner("Finished populating diagnostics")
    end)
  end
end

return M
