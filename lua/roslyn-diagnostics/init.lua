local log = require("vim.lsp.log")

local function close_unlisted_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.bo[buf].buflisted then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
end

local function unload_unlisted_buffers(buf)
  if not vim.bo[buf].buflisted then vim.api.nvim_buf_delete(buf, { unload = true }) end
end

local function get_or_create_buffer(filename)
  -- Check if buffer already exists
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == filename then return buf end
  end
  
  -- Use bufadd to create a buffer entry without loading the file
  -- This doesn't create conflicts like nvim_create_buf + nvim_buf_set_name
  return vim.fn.bufadd(filename)
end

local M = {}
M.options = {
  -- optional filter function to filter out files that should not be processed
  filter = function(filename) return (filename:match("%.cs$") or filename:match("%.fs$")) and not filename:match("/[ob][ij][bn]/") end,
  diagnostic_opts = false,
}

M.setup = function(options)
  options = options or {}

  M.options = vim.tbl_deep_extend("keep", options, M.options)
  if type(M.options.diagnostic_opts) == "table" or (type(M.options.diagnostic_opts) == "boolean" and M.options.diagnostic_opts == true) then vim.diagnostic.config(M.options.diagnostic_opts) end
  vim.api.nvim_create_user_command("RequestDiagnostics", function() M.request_diagnostics() end, {})
  vim.api.nvim_create_user_command("RequestDiagnosticErrors", function() M.request_diagnostics(1) end, {})
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

  return M.options
end

---@param severity integer | nil
M.request_diagnostics = function(severity)
  local severity_level = 4
  if severity ~= nil then severity_level = severity end

  close_unlisted_buffers()
  local spinner = require("roslyn-diagnostics.spinner").new()
  local clients = vim.lsp.get_clients({ name = "roslyn" })
  if not clients or #clients == 0 then
    vim.notify("Roslyn has not attached to the buffer yet.", vim.log.levels.ERROR)
    return
  end
  local client = clients[1]
  if client.name == "roslyn" then
    spinner:start_spinner("Populating workspace diagnostics")
    vim.diagnostic.reset()
    client.request("workspace/diagnostic", { previousResultIds = {} }, function(err, result, context, config)
      if err then
        local err_msg = string.format("diagnostics error - %s", vim.inspect(err))
        log.error(err_msg)
        spinner:stop_spinner("Error fetching diagnostics")
      end
      local ns = vim.lsp.diagnostic.get_namespace(client.id)

      if not result or not result.items then
        spinner:stop_spinner("No diagnostic results received")
        return
      end

      for _, per_file_diags in ipairs(result.items) do
        local filename = string.gsub(per_file_diags.uri, "file://", "")
        if M.options.filter(filename) then
          if per_file_diags.items ~= nil and #per_file_diags.items > 0 then
            local buf = get_or_create_buffer(filename)

            local file_diagnostics = require("roslyn-diagnostics.diagnostics").diagnostic_lsp_to_vim(per_file_diags.items, buf, context.client_id, severity_level)
            vim.diagnostic.set(ns, buf, file_diagnostics)
            vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
          end
        end
      end
      spinner:stop_spinner("Finished populating diagnostics")
    end)
  end
end

return M
