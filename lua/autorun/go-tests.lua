local config = require("autorun.config")
local default_opts = config.get_defaults()
local parsers = require('nvim-treesitter.parsers')
local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("go-tests")

local tests = {}
local output = {}

local function_names_query = [[
    (package_clause (package_identifier) @package)
    (function_declaration
        name: (identifier) @func_name
        (parameter_list
            (parameter_declaration) @type (#eq? @type "t *testing.T")
        )
        body: (block
            (expression_statement
                (call_expression
                    (selector_expression) @expr (#eq? @expr "t.Run")
                    (argument_list
                        (interpreted_string_literal) @func_sname
                        (func_literal
                            (parameter_list
                                (parameter_declaration) @stype (#eq? @stype "t *testing.T")
                            )
                        )
                    )
                )
            )
        )?
    )
]]

local find_lines = function(bufnr)
    local root
    local parser = parsers.get_parser(bufnr, "go")
    local first_tree = parser:trees()[1]
    if first_tree then
        root = first_tree:root()
    end
    local start_row, _, end_row, _ = root:range()
    local query = ts.query.parse("go", function_names_query)
    local names = {}
    for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
        local func_name
        for id, node in pairs(match) do
            local name = query.captures[id]
            if name == "func_name" then
                local row, col, _, _ = node:range()
                local pattern = "[^%w\']+"
                func_name = ts.get_node_text(node, 0)
                func_name = func_name:gsub("\"", "")
                func_name = func_name:gsub(pattern, "_")
                table.insert(names, {
                    name = func_name,
                    line = row,
                    col = col
                })
            end
            if name == "func_sname" then
                local row, col, _, _ = node:range()
                local pattern = "[^%w\']+"
                local func_sname = ts.get_node_text(node, 0)
                func_sname = func_sname:gsub("\"", "")
                func_sname = func_sname:gsub(pattern, "_")
                table.insert(names, {
                    name = func_name .. "/" .. func_sname,
                    line = row,
                    col = col
                })
            end
        end
    end
    for _, v in pairs(names) do
        local key = v.name
        if key and tests[key] then
            tests[key].line = v.line
            tests[key].col = v.col
            tests[key].bufnr = bufnr
        end
    end
end


-- TODO: save each extmark in a table and delete it when the test is fixed, use the line to detect the test

local show_results = function(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.diagnostic.reset(ns, bufnr)
    find_lines(bufnr)
    local diaginostics = {}
    for _, test in pairs(tests) do
        if test.success and test.line and bufnr == test.bufnr then
            local text = { "✓ PASS ", "RedrawDebugComposed" }
            vim.api.nvim_buf_set_extmark(bufnr, ns, test.line, 0, {
                virt_text = { text },
                virt_text_pos = "inline",
                sign_text = "✓",
            })
        end
        if test.failed and test.line and bufnr == test.bufnr then
            table.insert(diaginostics, {
                bufnr = bufnr,
                lnum = test.line,
                col = test.col,
                message = "FAIL ",
                severity = vim.diagnostic.severity.ERROR,
            })
        end
    end
    if #diaginostics > 0 then
        vim.diagnostic.set(ns, bufnr, diaginostics, {
            virtual_text = {
                virt_text_pos = "inline",
                spacing = 0,
                prefix = "✗",
            },
            signs = {
                text = { "✗" },
            }
        })
    end
end

local make_key = function(decoded)
    local key
    if decoded.Package ~= nil and decoded.Test ~= nil then
        local parts = vim.split(decoded.Package, "/")
        parts = vim.split(decoded.Test, "/")
        local func_name = decoded.Test
        for idx, part in ipairs(parts) do
            part = part:gsub("\"", "")
            part = part:gsub("[^%w\']+", "_")
            parts[idx] = part
        end
        func_name = table.concat(parts, "/")
        key = func_name
    end
    return key
end

local set_success_test = function(_, decoded)
    local key = make_key(decoded)
    if key ~= nil then
        tests[key] = {
            key = key,
            name = decoded.Test,
            success = true,
            failed = false,
        }
    end
end

local set_failed_test = function(_, decoded)
    local key = make_key(decoded)
    if key ~= nil then
        tests[key] = {
            key = key,
            name = decoded.Test,
            success = false,
            failed = true,
        }
    end
end

local add_test_output = function(decoded)
    local key, _ = make_key(decoded)
    if key ~= nil then
        if output[key] == nil then
            output[key] = {}
        end
        local out = decoded.Output:gsub("\n", "")
        if out ~= "" then
            table.insert(output[key], out)
        end
    end
end

local output_handler = function(bufnr)
    return function(_, data)
        for _, line in ipairs(data) do
            if not data then
                return
            end
            if line == "" then
                return
            end
            local success, decoded = pcall(vim.json.decode, line)
            if success then
                if decoded.Action == "pass" then
                    set_success_test(bufnr, decoded)
                end
                if decoded.Action == "fail" then
                    set_failed_test(bufnr, decoded)
                end
                if decoded.Action == "output" then
                    add_test_output(decoded)
                end
            end
        end
    end
end

-- DRY
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

local show_line_diagonstics = function(line)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    for _, test in pairs(tests) do
        if test.line == line then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, output[test.key])
            show_window(bufnr, default_opts.window)
        end
    end
end

local execute = function(bufnr, command, handler)
    vim.api.nvim_buf_create_user_command(bufnr, "GoTestDiag", function()
        local line = vim.fn.line(".") - 1
        show_line_diagonstics(line)
    end, {})
    vim.fn.jobstart(command, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = handler,
        on_stderr = handler,
        on_exit = function()
            show_results(bufnr)
        end
    })
end

local M = {}

M.autorun = function()
    -- TODO: create commands to start / stop the plugin
    local group = vim.api.nvim_create_augroup("WL", { clear = true })
    local command = vim.fn.split("go test ./... -json -short", " ")
    local pattern = "*.go"
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = pattern,
        callback = function()
            tests = {}
            output = {}
            local bufnr = vim.api.nvim_get_current_buf()
            execute(bufnr, command, output_handler(bufnr))
        end
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = pattern,
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            show_results(bufnr)
        end
    })
end

return M
