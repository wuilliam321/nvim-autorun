local M = {}

--[[
    setup the autorun plugin
]]
M.setup = function(opts)
    opts = opts or {}

    local cfg = require("autorun.config").set_defaults(opts)

    -- TODO: make it customizable by options
    if cfg.show_returns then
        require("autorun.go-returns").show_on_cursor_move()
    end

    -- TODO: make it customizable by options
    if cfg.go_tests then
        require("autorun.go-tests").autorun()
    end

    -- TODO: make it customizable by options
    require("autorun.autorun").setup()
end


return M
