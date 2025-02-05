# Workspace diagnostics for Roslyn language server

On demand generation of workspace diagnostics for your .NET project.

## 📦 Installation

```lua
-- lazy.nvim
{
  "bosvik/roslyn-diagnostics.nvim",
  -- lazy load on filetype
  ft = { "cs", "fs" },
  opts = { },
}
```

> [!IMPORTANT]
> For large solutions `roslyn.nvim` needs to be setup with
> `dotnet_analyzer_diagnostics_scope = "openFiles"` to avoid
> roslyn crashing.
>
>```lua
>  {
>    "seblj/roslyn.nvim",
>    ft = { "cs", "csproj" },
>    opts = {
>      config = {
>        settings = {
>          -- ...
>          ["csharp|background_analysis"] = {
>            dotnet_analyzer_diagnostics_scope = "openFiles",
>            dotnet_compiler_diagnostics_scope = "fullSolution",
>          },
>          -- ...
>        },
>      },
>      -- ...
>    }
>  }
>```
>
## ⚙ Configuration

You can configure a different function to filter which files should be processed.

```lua
-- lazy.nvim
{
  "bosvik/roslyn-diagnostics.nvim",
  ft = { "cs", "fs" },
  opts = {,
    -- Optional filter function to filter out files that should not be processed
    -- This is equivalent to the default filter.
    filter = function(filename) 
      return (filename:match("%.cs$") or filename:match("%.fs$")) and not filename:match("/[ob][ij][bn]/")
    end,
    -- set custom diagnostic opts
    -- refer :h vim.diagnostic.Opts
    diagnostic_opts = {
      virtual_text = {
        prefix = "●",
      },
      severity_sort = true,
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = "",
          [vim.diagnostic.severity.WARN] = "",
          [vim.diagnostic.severity.INFO] = "",
          [vim.diagnostic.severity.HINT] = "",
        },
      },
    },
  },
  keys = {
    { "<leader>cD", "<cmd>RequestDiagnostics<cr>", desc = "Request diagnostics", ft = { "cs", "fs" } },
  }
}
```

## 🚀 Usage

### Commands

| Function | Description |
| - | - |
|RequestDiagnostics| Get diagnostics, include ERROR, WARNING|
|RequestDiagnosticErrors| Only errors.|

### Autocommands

Adds autocmd on "LspAttach" and "InsertLeave" to refresh diagnostics of the buffer and refresh codelens.

## Credits

- [GustavEikaas](https://github.com/GustavEikaas/easy-dotnet.nvim): For one of the most vital plugins for .NET development. Also I stole your spinner module :sunglasses:
