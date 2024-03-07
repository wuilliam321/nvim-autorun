local config = require("autorun.config")

local default_opts = config.get_defaults()

local valid_output = function(data)
    return data and not (#data == 1 and data[1] == "")
end

local winnr = -1
local show_window = function(bufnr, opts)
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
    end
end

local write_data = function(bufnr, data)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, data)
end

local output_handler = function(bufnr)
    return function(_, data)
        if not valid_output(data) then
            return
        end

        show_window(bufnr, default_opts.window)
        write_data(bufnr, data)
    end
end

local execute = function(command, handler)
    vim.fn.jobstart(command, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = handler,
        on_stderr = handler,
    })
end


local M = {}

M.setup = function()
    print("setup autorun.autorun")
    vim.api.nvim_create_user_command("AutoRun", function()
        local group = vim.api.nvim_create_augroup("WL-ar", { clear = true })
        local bufnr = vim.api.nvim_create_buf(false, true)
        local command = vim.fn.split(vim.fn.input("Command> ", "go test ./..."), " ")
        local pattern = vim.fn.input("Pattern> ", "*.go")

        vim.api.nvim_create_autocmd("BufWritePost", {
            group = group,
            pattern = pattern,
            callback = function()
                execute(command, output_handler(bufnr))
            end
        })
    end, {})
end

return M
