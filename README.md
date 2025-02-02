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

## Credits

- [GustavEikaas](https://github.com/GustavEikaas/easy-dotnet.nvim): For one of the most vital plugins for .NET development. Also I stole your spinner module :sunglasses:
