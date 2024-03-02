local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function P(o)
    return print(dump(o))
end

local parsers = require('nvim-treesitter.parsers')
-- local query = require('nvim-treesitter.query')
local ts = vim.treesitter
-- local ts_utils = require 'nvim-treesitter.ts_utils'
local ns = vim.api.nvim_create_namespace("go-tests")

local tests = {}
local success = {}

local find_lines = function(bufnr)
    local root
    local parser = parsers.get_parser(bufnr, "go")
    local first_tree = parser:trees()[1]

    if first_tree then
        root = first_tree:root()
    end
    local start_row, _, end_row, _ = root:range()

    -- local root = parser:parse()[1]
    local query = ts.query.parse("go", [[
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
    ]])


    local names = {}
    local pkg = ""
    for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
        local func_name
        for id, node in pairs(match) do
            local name = query.captures[id]

            if name == "func_name" then
                local line = node:range() + 1
                local pattern = "[^%w\']+"
                func_name = ts.get_node_text(node, 0)
                func_name = func_name:gsub("\"", "")
                func_name = func_name:gsub(pattern, "_")
                table.insert(names, { name = func_name, line = line })
            end

            if name == "func_sname" then
                local line = node:range() + 1
                local pattern = "[^%w\']+"
                local func_sname = ts.get_node_text(node, 0)
                func_sname = func_sname:gsub("\"", "")
                func_sname = func_sname:gsub(pattern, "_")
                table.insert(names, { name = func_name .. "/" .. func_sname, line = line })
            end

            if name == "package" and pkg == "" then
                pkg = ts.get_node_text(node, 0)
            end
        end
    end

    for _, v in pairs(names) do
        local key = pkg .. "/" .. v.name
        print("key", pkg, key)
        if key and success[key] then
            success[key].Line = v.line
        end
    end
    -- print("tests", vim.inspect(tests))
end


local execute = function(command, handler)
    vim.fn.jobstart(command, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = handler,
        on_stderr = handler,
        on_exit = function()
            local bufnr = vim.api.nvim_get_current_buf()
            find_lines(bufnr)
            print("success", vim.inspect(success))
        end
    })
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
            local decoded = vim.json.decode(line)

            if decoded.Action == "pass" then
                -- print("decoded", vim.inspect(decoded))
                local key
                local pkg

                if decoded.Package ~= nil and decoded.Test ~= nil then
                    local parts = vim.split(decoded.Package, "/")
                    pkg = parts[#parts]
                    key = pkg .. "/" .. decoded.Test
                end

                if key ~= nil then
                    success[key] = {
                        key = key,
                        name = decoded.Test,
                        package = pkg,
                    }
                end
            end
        end
    end
end


vim.api.nvim_create_user_command("GoTests", function()
    local group = vim.api.nvim_create_augroup("WL", { clear = true })
    local bufnr = vim.api.nvim_create_buf(false, true)
    -- local command = vim.fn.split(vim.fn.input("Command> ", "go test ./... -json"), " ")
    -- local pattern = vim.fn.input("Pattern> ", "*.go")
    local command = vim.fn.split("go test ./... -json", " ")
    local pattern = "*.go"

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = pattern,
        callback = function()
            execute(command, output_handler(bufnr))
        end
    })
end, {})
