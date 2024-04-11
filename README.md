# AutoRun (tests)

## Requirements
 * [Neovim](https://neovim.io/) 0.9.0 or above

## Install
You can use any nvim package manager, for example, using packer.nvim:

```lua
    ...
    use {
        'wuilliam321/nvim-autorun',
        config = function()
            local w = math.floor(vim.api.nvim_win_get_width(0))
            local h = math.floor(vim.api.nvim_win_get_height(0) / 4)
            require('autorun').setup({
              show_returns = true,
              go_tests = true,
              window = {
                relative = 'editor',
                height = h,
                width = w,
                top = h * 3,
                left = 0,
                style = 'minimal',
                border = 'double',
                transparent = 10,
              }
            })
        end
    }
```
