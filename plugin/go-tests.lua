local parsers = require('nvim-treesitter.parsers')
local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("go-tests")

local tests = {}

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
    local pkg = ""
    for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
        local func_name
        for id, node in pairs(match) do
            local name = query.captures[id]
            if name == "func_name" then
                local line = node:range()
                local pattern = "[^%w\']+"
                func_name = ts.get_node_text(node, 0)
                func_name = func_name:gsub("\"", "")
                func_name = func_name:gsub(pattern, "_")
                table.insert(names, { name = func_name, line = line })
            end
            if name == "func_sname" then
                local line = node:range()
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
        if key and tests[key] then
            tests[key].line = v.line
        end
    end
end

local show_results = function(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.diagnostic.reset(ns, bufnr)
    local diaginostics = {}
    for _, test in pairs(tests) do
        if test.success and test.line then
            local text = { "✓ Test pass", "@string" }
            vim.api.nvim_buf_set_extmark(bufnr, ns, test.line, 0, {
                virt_text = { text },
            })
        end
        if test.failed and test.line then
            local d = {
                bufnr = bufnr,
                lnum = test.line,
                col = 0,
                message = "✗ Test failed",
                severity = vim.diagnostic.severity.ERROR,
            }
            table.insert(diaginostics, d)
        end
    end
    if #diaginostics > 0 then
        print("d", vim.inspect(diaginostics))
        vim.diagnostic.set(ns, bufnr, diaginostics, {})
    end
end

local set_success_test = function(decoded)
    local key
    local pkg
    if decoded.Package ~= nil and decoded.Test ~= nil then
        local parts = vim.split(decoded.Package, "/")
        pkg = parts[#parts]
        key = pkg .. "/" .. decoded.Test
    end
    if key ~= nil then
        tests[key] = {
            key = key,
            name = decoded.Test,
            package = pkg,
            success = true,
            failed = false,
        }
    end
end

local set_failed_test = function(decoded)
    local key
    local pkg
    if decoded.Package ~= nil and decoded.Test ~= nil then
        local parts = vim.split(decoded.Package, "/")
        pkg = parts[#parts]
        key = pkg .. "/" .. decoded.Test
    end
    if key ~= nil then
        tests[key] = {
            key = key,
            name = decoded.Test,
            package = pkg,
            success = false,
            failed = true,
        }
    end
end

local output_handler = function(_, data)
    for _, line in ipairs(data) do
        if not data then
            return
        end
        if line == "" then
            return
        end
        local decoded = vim.json.decode(line)
        if decoded.Action == "pass" then
            set_success_test(decoded)
        end
        if decoded.Action == "fail" then
            set_failed_test(decoded)
        end
    end
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
            show_results(bufnr)
        end
    })
end

vim.api.nvim_create_user_command("GoTests", function()
    local group = vim.api.nvim_create_augroup("WL", { clear = true })
    local bufnr = vim.api.nvim_create_buf(false, true)
    local command = vim.fn.split("go test ./... -json -short", " ")
    local pattern = "*.go"
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = pattern,
        callback = function()
            execute(command, output_handler)
        end
    })
end, {})
