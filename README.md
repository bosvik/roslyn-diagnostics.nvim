# Workspace diagnostics for Roslyn language server

On demand generation of workspace diagnostics for your .NET project.

## Installation

```lua
-- lazy.nvim
{
  "bosvik/roslyn-diagnostics.nvim",
  opts = {},
  keys = {
    {
      "<leader>cD",
      "<cmd>RequestDiagnostics<cr>",
      desc = "Request diagnostics",
    },
  }
}
```
