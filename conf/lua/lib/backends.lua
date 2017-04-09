local dyups = require 'ngx.dyups'

local registered_backends = {}

local _M = {}

function _M.register_backend(name, conf)
    if registered_backends[name] ~= conf then
        registered_backends[name] = conf
        ngx.log(ngx.INFO, 'Created/Updated backend ' .. name .. ' as ' .. conf)
        dyups.update(name, conf)
    end
end

return _M
