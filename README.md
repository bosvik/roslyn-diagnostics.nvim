# Workspace diagnostics for Roslyn language server

On demand generation of workspace diagnostics for your .NET project.

## Installation

```lua
-- lazy.nvim
{
  "bosvik/roslyn-diagnostics.nvim",
  opts = {},
  ft = { "cs" },
  keys = {
    {
      "<leader>cD",
      "<cmd>RequestDiagnostics<cr>",
      desc = "Request diagnostics",
      ft = { "cs" },
    },
  }
}
```

> [!IMPORTANT]
> For large solutions `roslyn.nvim` needs to be setup with
> `dotnet_analyzer_diagnostics_scope = "openFiles"` to avoid
> roslyn crashing.

```lua
  {
    "seblj/roslyn.nvim",
    ft = { "cs", "csproj" },
    opts = function()
      vim.api.nvim_create_autocmd({ "LspAttach", "InsertLeave" }, {
        pattern = "*.cs",
        callback = function()
          vim.defer_fn(function()
            local clients = vim.lsp.get_clients({ name = "roslyn" })
            if not clients or #clients == 0 then
              return
            end

            local buffers = vim.lsp.get_buffers_by_client_id(clients[1].id)
            for _, buf in ipairs(buffers) do
              vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
              vim.lsp.codelens.refresh()
            end
          end, 100)
        end,
      })
      return {
        config = {
          settings = {
            -- ...
            ["csharp|background_analysis"] = {
              dotnet_analyzer_diagnostics_scope = "openFiles",
              dotnet_compiler_diagnostics_scope = "fullSolution",
            },
            -- ...
          },
        },
        -- ...
      }
    end
  }
```

## Credits

- [GustavEikaas](https://github.com/GustavEikaas/easy-dotnet.nvim): For one of the most vital plugins for .NET development. Also I stole your spinner module :sunglasses:
