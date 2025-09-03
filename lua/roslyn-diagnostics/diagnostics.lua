local M = {}

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
---@param severity_level integer
---@return vim.Diagnostic[]
M.diagnostic_lsp_to_vim = function(diagnostics, bufnr, client_id, severity_level)
  local client = vim.lsp.get_client_by_id(client_id)
  local buf_lines = get_buf_lines(bufnr)

  local offset_encoding = client and client.offset_encoding or "utf-16"
  --- @param diagnostic lsp.Diagnostic
  --- @return vim.Diagnostic
  return vim.tbl_filter(
    function(item) return item ~= nil end,
    vim.tbl_map(function(diagnostic)
      local start = diagnostic.range.start
      local _end = diagnostic.range["end"]
      local message = diagnostic.message
      local severity = severity_lsp_to_vim(diagnostic.severity)
      if type(message) ~= "string" then
        vim.notify_once(string.format("Unsupported Markup message from LSP client %d", client_id), 4)
        message = diagnostic.message.value
      end
      -- return vim.tbl_map(function(diagnostic)
      --   local start = diagnostic.range.start
      --   local _end = diagnostic.range["end"]
      --   local message = diagnostic.message
      --   local severity = severity_lsp_to_vim(diagnostic.severity)
      --   if type(message) ~= "string" then
      --     vim.notify_once(string.format("Unsupported Markup message from LSP client %d", client_id), 4)
      --     message = diagnostic.message.value
      --   end

      if severity <= severity_level then
        --- @type vim.Diagnostic
        return {
          lnum = start.line,
          col = line_byte_from_position(buf_lines, start.line, start.character, offset_encoding),
          end_lnum = _end.line,
          end_col = line_byte_from_position(buf_lines, _end.line, _end.character, offset_encoding),
          severity = severity,
          message = message,
          source = diagnostic.source,
          code = diagnostic.code,
          _tags = tags_lsp_to_vim(diagnostic, client_id),
          user_data = {
            lsp = diagnostic,
          },
        }
      end
      return nil
    end, diagnostics)
  )
end

return M
