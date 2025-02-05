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
M.options = {
  -- optional filter function to filter out files that should not be processed
  filter = function(filename) return (filename:match("%.cs$") or filename:match("%.fs$")) and not filename:match("/[ob][ij][bn]/") end,
}

M.setup = function(options)
  options = options or {}

  M.options = vim.tbl_deep_extend("keep", options, M.options)

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

  return M.options
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
        if M.options.filter(filename) then
          if per_file_diags.items ~= nil and #per_file_diags.items > 0 then
            local buf = find_buf_or_make_unlisted(filename)

            local file_diagnostics = require("roslyn-diagnostics.diagnostics").diagnostic_lsp_to_vim(per_file_diags.items, per_file_diags.uri, buf, context.client_id)
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
