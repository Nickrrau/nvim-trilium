# nvim-trilium

Trilium notes in Neovim over ETAPI. Needs `curl`.

```lua
{
  "nickrrau/nvim-trilium",
  opts = {
    -- url = "http://127.0.0.1:37840",
    -- token = os.getenv("TRILIUM_ETAPI_TOKEN"),
    -- parent = "nvim-notes", -- title or id under Trilium root
  },
}
```

| Command | |
|---|---|
| `:TriliumList [id]` | Browse children of `parent` (default `nvim-notes`) |
| `:TriliumOpen [path]` | Open id/title/`a/b/note`; missing path creates it |
| `:TriliumSave` | Save current note (`:w` also works) |

List: `<CR>` enter or open, `o` open content, `-` up, `r` refresh, `q` close.
