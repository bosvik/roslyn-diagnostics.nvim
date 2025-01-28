---@param lines string[]?
---@param lnum integer
---@param col integer
---@param offset_encoding string
---@return integer
local function line_byte_from_position(lines, lnum, col, offset_encoding)
	if not lines or offset_encoding == "utf-8" then
		return col
	end

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
		return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	local f = io.open(filename)
	if not f then
		return
	end

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
local function diagnostic_lsp_to_vim(diagnostics, bufnr, client_id)
	local buf_lines = get_buf_lines(bufnr)
	local client = vim.lsp.get_client_by_id(client_id)
	local offset_encoding = client and client.offset_encoding or "utf-16"
	--- @param diagnostic lsp.Diagnostic
	--- @return vim.Diagnostic
	return vim.tbl_map(function(diagnostic)
		local start = diagnostic.range.start
		local _end = diagnostic.range["end"]
		local message = diagnostic.message
		if type(message) ~= "string" then
			vim.notify_once(
				string.format("Unsupported Markup message from LSP client %d", client_id),
				vim.lsp.log_levels.ERROR
			)
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
local M = {}
M.setup = function()
	vim.api.nvim_create_user_command("RequestDiagnostics", function()
		M.request_diagnostics()
	end, {})
end

M.request_diagnostics = function()
	local clients = vim.lsp.get_clients({ name = "roslyn" })
	if not clients or #clients == 0 then
		return
	end
	local client = clients[1]
	if client.name == "roslyn" then
		client.request("workspace/diagnostic", { previousResultIds = {} }, function(err, result, context, config)
			local ns = vim.lsp.diagnostic.get_namespace(client.id)
			vim.notify("Finished diagnostics on the workspace")

			local function find_buf_or_make_unlisted(file_name)
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_get_name(buf) == file_name then
						return buf
					end
				end

				local buf = vim.api.nvim_create_buf(false, false)
				vim.api.nvim_buf_set_name(buf, file_name)
				return buf
			end

			for _, per_file_diags in ipairs(result.items) do
				local filename = string.gsub(per_file_diags.uri, "file://", "")
				if
					string.find(filename, "%.cs$")
					and not string.find(filename, "/obj/")
					and not string.find(filename, "/bin/")
				then
					if per_file_diags.items ~= nil and #per_file_diags.items > 0 then
						local buf = find_buf_or_make_unlisted(filename)
						vim.diagnostic.set(ns, buf, diagnostic_lsp_to_vim(per_file_diags.items, buf, context.client_id))
					end
				end
			end
		end)
	end
end
return M
