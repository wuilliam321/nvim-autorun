local M = {}

--[[
    setup the autorun plugin
]]
M.setup = function(opts)
    opts = opts or {}

    require("autorun.config").set_defaults(opts)
end


return M
