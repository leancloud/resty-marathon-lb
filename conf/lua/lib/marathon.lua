-- requires --
local lock       = require 'resty.lock'
local http       = require 'resty.http'
local cjson      = require 'cjson'
local stalecache = require 'stalecache'

local re_match = ngx.re.match
local timer_at = ngx.timer.at

local die = require('utils').die

-- code --
local _M = {}

local cache = stalecache.new('marathon_upstream', 'marathon_upstream_lock', 10)

local function build_upstream(resp, port)
    resp = cjson.decode(resp)
    if not resp then
        return false
    end

    local rst = ''
    local other = resp.app.labels['nginx-' .. port]
    if other ~= nil then
        rst = other
    end

    local idx = 0
    for i, p in ipairs(resp.app.ports) do
        if p == port then
            idx = i
            break
        end
    end
    for i, t in ipairs(resp.app.tasks) do
        rst = rst .. 'server ' .. t.host .. ':' .. t.ports[idx] ..'; '
    end
    return rst
end

function cache.fill(self, key, stale_data)
    local app_name = key

    local parsed, err = re_match(app_name, [[([a-z0-9_\-]+(:[0-9]+)?)#([a-z0-9_/\-]+):([0-9]+)]])
    if not parsed then
        die('Invalid app_name: ' .. app_name)
    end
    local marathon = parsed[1]
    local id = parsed[3]
    local port = parsed[4]

    local sess = http:new()
    sess:set_timeout(3000)
    -- local resp, err = sess:request_uri(os.getenv('MARATHON') .. '/v2/apps/' .. id)
    ---[[ --]] ngx.log(ngx.NOTICE, 'Request marathon!')
    local resp, err = sess:request_uri('http://' .. marathon .. '/v2/apps/' .. id)
    if not resp then
        ngx.log(ngx.CRIT, 'Failed to request marathon for ' .. app_name .. '!')
        if stale_data == nil then
            -- Bail out
            return false
        end
        return stale_data
    end
    ---[[ --]] ngx.log(ngx.NOTICE, resp['status'] .. '  ' .. resp['body'])

    local upstream
    if resp['status'] == 200 then
        upstream = build_upstream(resp['body'], tonumber(port))
    elseif resp['status'] == 404 then
        upstream = false
    else
        upstream = false
        ngx.log(
            ngx.ERR,
            "Marathon returned non-200 code for " .. app_name ..
            "Code: " .. resp['status']
        )
    end
    return upstream
end

function _M.get_upstream(app_name)
    local upstream = cache:get(app_name)
    if not upstream then
        die("Failed to request marathon.")
    end
    return upstream
end

return _M
