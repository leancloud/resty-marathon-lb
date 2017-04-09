-- requires --
local lock     = require 'resty.lock'
local http     = require 'resty.http'
local cjson    = require 'cjson'

local re_match = ngx.re.match
local timer_at = ngx.timer.at
local ngx_shared = ngx.shared
local os_time = os.time

local die = require('utils').die

-- code --
local _M = {}
local mt = { __index = _M }

function _M.new(data_dict_name, lock_dict_name, ttl)
    if not ngx_shared[data_dict_name] then
        error('No shared dict named ' .. data_dict_name)
    elseif not ngx_shared[lock_dict_name] then
        error('No shared dict named ' .. lock_dict_name)
    end

    return setmetatable({
        data_dict_name = data_dict_name,
        lock_dict_name = lock_dict_name,
        ttl = ttl,
    }, mt)
end

function _M.fill(self, key, stale_data)
    -- Should return data for filling
    -- nil indicates failure, in this situation
    -- stale data will be refreshed for another ttl
    error('Should override this')
end

function _M.get(self, key)
    local now = os_time()

    local shdata = ngx_shared[self.data_dict_name]
    local data, expire = shdata:get(key)
    if data ~= nil and now < expire then
        return data
    end

    -- Update cache
    local datalock = lock:new(self.lock_dict_name, { timeout = 0 })
    local locked = datalock:lock(key)
    if not locked then
        -- Some other worker grabed the lock, they will update cache, we just use stale conf
        ---[[ --]] ngx.log(ngx.NOTICE, 'No lock, return stale')
        if data == nil then
            -- Well, no data, let's wait
            ---[[ --]] ngx.log(ngx.NOTICE, 'No data, wait')
            datalock = lock:new(self.lock_dict_name)
            datalock:lock(key)
        else
            return data
        end
    end
    ---[[ --]] ngx.log(ngx.NOTICE, 'Locked!')

    timer_at(0, function(premature, key, datalock)
        -- 2nd try, other worker may have updated the cache
        local now = os_time()

        local shdata = ngx_shared[self.data_dict_name]
        local data, expire = shdata:get(key)
        if data ~= nil and now < expire then
            ---[[ --]] ngx.log(ngx.NOTICE, 'Some other have done the work')
            datalock:unlock()
            return
        end

        local new_data = self:fill(key, data)
        if new_data ~= nil then
            -- Refresh stale data if fill failed
            data = new_data
        end
        ---[[ --]] ngx.log(ngx.NOTICE, 'Set cache!')
        shdata:set(key, data, 0, os_time() + self.ttl)
        datalock:unlock()
    end, key, datalock)

    if data then
        -- Serve stale data
        return data
    else
        -- No stale data, wait for filling
        datalock = lock:new(self.lock_dict_name)
        datalock:lock(key)
        datalock:unlock()

        local data, expire = shdata:get(key)
        if not data then
            -- Oh shit...
            return nil
        end
        return data
    end
end

return _M
