# iso8583

## Requirements
 * [Neovim](https://neovim.io/) 0.9.0 or above

## Install
You can use any nvim package manager, for example, using packer.nvim:

```lua
    ...
    use {
        'wuilliam321/nvim-autorun',
        config = function()
            require('autorun').setup({
                window = {
                    relative = 'editor',
                    height = vim.api.nvim_win_get_height(0) - 2,
                    width = 92,
                    top = 0,
                    left = 149,
                    style = 'minimal',
                    border = 'double',
                    transparent = 10,
                }
            })
        end
    }
```

## Usage

You just need to run `:AutoRun`, it will run after save
