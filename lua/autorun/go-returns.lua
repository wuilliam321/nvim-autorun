local parsers = require("nvim-treesitter.parsers")
local ts = vim.treesitter
local ns = vim.api.nvim_create_namespace("go-returns")

local function get_visible_viewport()
	local current_win = vim.api.nvim_get_current_win()
	local win_height = vim.api.nvim_win_get_height(current_win)

	local first_line = vim.fn.line("w0") -- Get the first visible line
	local last_line = first_line + win_height - 1 -- Calculate the last visible line

	return first_line, last_line
end

local function function_definition_types(definition)
	local pattern = "%b() %((.-)%)$"
	-- Extract return types using the Lua regex pattern
	definition = vim.fn.split(definition, "\n")[1]
	local types = {}
	local returnTypesString = string.match(definition, pattern)
	if returnTypesString then
		for returnType in string.gmatch(returnTypesString, "([^,]+)") do
			table.insert(types, returnType:match("%s*(.-)%s*$"))
		end
	end
	if #types == 0 then
		-- If no return types are found, try to match a single return type
		local singleReturnType = string.match(definition, "%b() ([^%s,]+)$")
		if singleReturnType then
			table.insert(types, singleReturnType)
		end
	end
	if #types == 0 then
		-- If no return types are found, try to match a single return type
		local singleReturnType = string.match(definition, "%b() (%<%-chan%s+[^%s,%)]+)")
		if singleReturnType then
			table.insert(types, singleReturnType)
		end
	end
	return types
end

local call_query = [[
(call_expression
    function: (identifier) @call)

(call_expression
    function: (selector_expression
        field: (field_identifier) @call))
]]

local return_types = {}
local extract_node_return_types = function(node, results)
	if not results then
		return
	end
	for _, result in pairs(results) do
		if not result then
			return
		end
		if result.error then
			return
		end
		if not result.result then
			return
		end

		local type
		local function_definition = string.match(result.result.contents.value, "```go\n(.*)\n```")

		local types = function_definition_types(function_definition)
		if #types == 1 then
			type = types[1]
		end

		if #types > 1 then
			type = table.concat(types, ", ")
		end

		if type then
			local line, _, _, _ = node:range()
			table.insert(return_types, {
				text = type,
				line = line,
			})
		end
	end
end

local show_return_types = function(from, to)
	vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

	local root
	local parser = parsers.get_parser(0, "go")
	local first_tree = parser:trees()[1]
	if first_tree then
		root = first_tree:root()
	end

	local start_row, _, end_row, _ = root:range()
	if from and to then
		start_row = from
		end_row = to
	end

	return_types = {}
	local query = ts.query.parse("go", call_query)
	for _, match, _ in query:iter_matches(root, 0, start_row, end_row) do
		for id, node in pairs(match) do
			local name = query.captures[id]
			if name == "call" then
				local line, col, next_line, _ = node:range()
				-- if line is in between from and to
				if line >= from and line < to then
					local params = vim.lsp.util.make_position_params()
					params.position.line = line
					params.position.character = col
					local results = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 1000)
					extract_node_return_types(node, results)
				end
			end
		end
	end
	-- vim.defer_fn(function()
	if #return_types == 0 then
		return
	end
	for _, r in pairs(return_types) do
		vim.api.nvim_buf_set_extmark(0, ns, r.line, -1, {
			virt_text = { { "-> (" .. r.text .. ")", { "CursorColumn", "@attribute" } } },
		})
	end
	-- end, 200)
end

-- TODO: make a better refresh, maybe with a timer, maybe debounce

-- -- vim.api.nvim_create_user_command("GoReturns", function()
-- local group = vim.api.nvim_create_augroup("WLa", { clear = true })
-- vim.api.nvim_create_autocmd({ "CursorMoved" }, {
--     group = group,
--     pattern = "*.go",
--     callback = function()
--         -- Example usage
--         local first_line, last_line = getVisibleViewport()
--         show_return_types(first_line, last_line)
--     end
-- })
-- -- end, {})

local function debounce(func, timeout)
	local timer_id
	return function(...)
		if timer_id ~= nil then
			vim.fn.timer_stop(timer_id)
		end
		local args = { ... }
		timer_id = vim.fn.timer_start(timeout, function()
			func(unpack(args))
		end)
	end
end

local M = {}

M.show_on_save = function()
	-- TODO: create commands to show and hide return types
	local first_line, last_line = get_visible_viewport()
	show_return_types(first_line, last_line)
	local group = vim.api.nvim_create_augroup("WLav", { clear = true })
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		group = group,
		pattern = "*.go",
		callback = function()
			first_line, last_line = get_visible_viewport()
			show_return_types(first_line, last_line)
		end,
	})
end

M.show_on_cursor_move = function()
	local current_line = vim.fn.line(".")
	show_return_types(current_line - 1, current_line)
	local group = vim.api.nvim_create_augroup("WLam", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorHold" }, {
		group = group,
		pattern = "*.go",
		callback = debounce(function()
			current_line = vim.fn.line(".")
			show_return_types(current_line - 1, current_line)
		end, 100),
	})
end

return M
