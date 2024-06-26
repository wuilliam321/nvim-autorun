local config = require("autorun.config")
local window = require("autorun.window")
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
    (function_declaration
      name: (identifier) @func_name
      (parameter_list
          (parameter_declaration) @type (#eq? @type "t *testing.T")
      )
      body: (block
        (short_var_declaration
          left: (expression_list
            (identifier) @tt (#eq? @tt "tt"))
          right: (expression_list
            (composite_literal
              body: (literal_value
                (literal_element
                  (literal_value
                    (keyed_element
                      (literal_element
                        (identifier) @tid (#eq? @tid "name")
                      )
                      (literal_element
                        (interpreted_string_literal) @tc
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
    (function_declaration
      name: (identifier) @func_name
      (parameter_list
          (parameter_declaration) @type (#eq? @type "t *testing.T")
      )
      body: (block
        (short_var_declaration
          left: (expression_list
            (identifier) @tt (#eq? @tt "tt"))
          right: (expression_list
            (composite_literal
              body: (literal_value
                (literal_element
                  (literal_value
                    . (literal_element
                        (interpreted_string_literal) @tc
                    )
                  )
                )
              )
            )
          )
        )
      )
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
    local pkg_name = ""
    for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
        local func_name
        for id, node in pairs(match) do
            local name = query.captures[id]
            if name == "package" then
                pkg_name = ts.get_node_text(node, 0)
                if string.find(pkg_name, "_test") then
                    pkg_name = pkg_name:gsub("_test", "")
                end
            end
            if name == "func_name" then
                local row, col, _, _ = node:range()
                local pattern = "[^%w\']+"
                func_name = ts.get_node_text(node, 0)
                func_name = func_name:gsub("\"", "")
                func_name = func_name:gsub(pattern, "_")
                local n = pkg_name .. "_" .. func_name
                table.insert(names, {
                    name = n,
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
                local n = pkg_name .. "_" .. func_name .. "/" .. func_sname
                table.insert(names, {
                    name = n,
                    line = row,
                    col = col
                })
            end
            if name == "tc" then
                local row, col, _, _ = node:range()
                local pattern = "[^%w\']+"
                local func_sname = ts.get_node_text(node, 0)
                func_sname = func_sname:gsub("\"", "")
                func_sname = func_sname:gsub(pattern, "_")
                local n = pkg_name .. "_" .. func_name .. "/" .. func_sname
                table.insert(names, {
                    name = n,
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


local clear_marks = function(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.diagnostic.reset(ns, bufnr)
end

-- TODO: save each extmark in a table and delete it when the test is fixed, use the line to detect the test

local show_results = function(bufnr)
    clear_marks(bufnr)

    find_lines(bufnr)
    local diaginostics = {}
    for _, test in pairs(tests) do
        if test.success and test.line and bufnr == test.bufnr then
            local text = { " ✓ PASS ", "RedrawDebugComposed" }
            vim.api.nvim_buf_set_extmark(bufnr, ns, test.line, -1, {
                virt_text = { text },
                virt_text_pos = "eol",
                -- spacing = 1,
                sign_text = "✓",
            })
        end
        if test.failed and test.line and bufnr == test.bufnr then
            local t = {
                bufnr = bufnr,
                lnum = test.line,
                col = test.col,
                message = "✗ Test " .. test.name .. " FAIL ",
                severity = vim.diagnostic.severity.ERROR,
            }
            table.insert(diaginostics, t)
        end
    end
    if #diaginostics > 0 then
        vim.diagnostic.set(ns, bufnr, diaginostics, {
            virtual_text = {
                virt_text_pos = "eol",
                spacing = 1,
                prefix = "",
                sign_text = "✗",
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
        local parts = vim.split(decoded.Test, "/")
        local func_name = decoded.Test
        for idx, part in ipairs(parts) do
            part = part:gsub("\"", "")
            part = part:gsub("[^%w\']+", "_")
            parts[idx] = part
        end
        func_name = table.concat(parts, "/")

        local pkg_parts = vim.split(decoded.Package, "/")
        if #pkg_parts > 3 then
            local pkg_name = pkg_parts[#pkg_parts]
            if string.find(pkg_name, "_test") then
                pkg_name = pkg_name:gsub("_test", "")
            end
            key = pkg_name .. "_" .. func_name
        end
        -- TODO: just for the tests on golang root projects, assuming package name is main
        if #pkg_parts == 3 then
            key = "main" .. "_" .. func_name
        end
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

local winnr = -1
local show_line_diagonstics = function(line)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    for _, test in pairs(tests) do
        if test.line == line then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, output[test.key])
            winnr = window.show(winnr, bufnr, default_opts.window)
        end
    end
end

local execute = function(bufnr, command, handler)
    if vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_win_close(winnr, true)
    end

    clear_marks(bufnr)

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
            -- TODO: aqui puede ir el llamada de nuevo, desde cache, para mostrar el output
        end
    })
end

local test_method = function(bufnr)
    tests = {}
    output = {}
    local func_name = vim.fn['cfi#format']("%s", "")
    if not func_name or func_name == "" then
        return
    end
    func_name = func_name:gsub("\"", "")
    func_name = func_name:gsub("[^%w\']+", "_")
    local cmd = vim.fn.split(string.format("go test ./... -run %s -json -short -v", func_name), " ")
    execute(bufnr, cmd, output_handler(bufnr))
end

local test_all = function(bufnr)
    tests = {}
    output = {}
    local command = vim.fn.split("go test ./... -json -short -v", " ")
    execute(bufnr, command, output_handler(bufnr))
end

local M = {}

M.autorun = function()
    local group = vim.api.nvim_create_augroup("WL", { clear = true })
    local pattern = "*.go"

    if default_opts.run_on_save then
        vim.api.nvim_create_autocmd("BufWritePost", {
            group = group,
            pattern = pattern,
            callback = function()
                test_all(vim.api.nvim_get_current_buf())
            end
        })
    end

    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = pattern,
        callback = function()
            show_results(vim.api.nvim_get_current_buf())
        end
    })

    vim.api.nvim_create_user_command("GoTestMethod", function()
        test_method(vim.api.nvim_get_current_buf())
    end, {})

    vim.api.nvim_create_user_command("GoTestAll", function()
        test_all(vim.api.nvim_get_current_buf())
    end, {})
end


return M
