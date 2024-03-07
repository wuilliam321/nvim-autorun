local M = {}

--[[
    setup the autorun plugin
]]
M.setup = function(opts)
    opts = opts or {}

    local cfg = require("autorun.config").set_defaults(opts)

    if cfg.show_returns then
        require("autorun.go-returns").show()
    end

    if cfg.go_tests then
        require("autorun.go-tests").autorun()
    end
end


return M
