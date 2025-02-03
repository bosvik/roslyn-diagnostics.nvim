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
    opts = {
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
  }
```

## Credits

- [GustavEikaas](https://github.com/GustavEikaas/easy-dotnet.nvim): For one of the most vital plugins for .NET development. Also I stole your spinner module :sunglasses:
