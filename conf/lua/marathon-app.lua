local marathon = require 'marathon'
local backends = require 'backends'
local die = require('utils').die

local marathon_app = ngx.var.marathon_app;
local upstream = marathon.get_upstream(marathon_app)

if not upstream then
  die('No upstream for ' .. marathon_app)
end

local target = marathon_app:gsub('[/:#]', '-')
backends.register_backend(target, upstream)
ngx.var.upstream = target
