local config = require("autorun.config")
local window = require("autorun.window")

local default_opts = config.get_defaults()

local valid_output = function(data)
    return data and not (#data == 1 and data[1] == "")
end

local winnr = -1
local output_handler = function(bufnr)
    return function(_, data)
        -- TODO: put the whole output into a buffer to be able to view it later
        if not valid_output(data) then
            return
        end
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, data)
        winnr = window.show(winnr, bufnr, default_opts.window)
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
    -- vim.api.nvim_create_user_command("AutoRun", function()
    local group = vim.api.nvim_create_augroup("WL-ar", { clear = true })
    local bufnr = vim.api.nvim_create_buf(false, true)
    -- local command = vim.fn.split(vim.fn.input("Command> ", "go test ./..."), " ")
    -- local pattern = vim.fn.input("Pattern> ", "*.go")
    local command = vim.fn.split("go test ./... -short")
    local pattern = "*.go"

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = pattern,
        callback = function()
            execute(command, output_handler(bufnr))
        end
    })
    -- end, {})
end

return M
