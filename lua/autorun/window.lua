local M = {}

M.show = function(winnr, bufnr, opts)
    if not vim.api.nvim_win_is_valid(winnr) then
        winnr = vim.api.nvim_open_win(bufnr, false, {
            relative = opts.relative,
            row = opts.top,
            col = opts.left,
            width = opts.width,
            height = opts.height,
            style = opts.style,
            border = opts.border,
        })
        vim.api.nvim_set_option_value('winblend', opts.transparent, { win = winnr })
        vim.api.nvim_set_option_value('wrap', true, { win = winnr })
    end
    return winnr
end

return M
