local config = {}

local default_config = {
    window = {
        relative = 'editor',
        height = vim.api.nvim_win_get_height(0),
        width = vim.api.nvim_win_get_width(0) / 2,
        top = vim.api.nvim_win_get_height(0),
        left = vim.api.nvim_win_get_width(0) / 2,
        style = 'minimal',
        border = 'single',
        transparent = 50,
    }
}

config.set_defaults = function(opts)
    config = vim.tbl_extend("force", default_config, opts)
end

config.get_defaults = function()
    return config
end

return config
