local _M = {}

function _M.die(fail_say)
    local ctype = ngx.req.get_headers()['Content-Type']
    ngx.status = 500
    if type(ctype) == "string" and ctype:find("application/json") ~= nil then
        ngx.header['Content-Type'] = 'application/json'
        ngx.say([[{"error": true, "reason": "]] .. fail_say .. [["}]])
    else
        ngx.say(fail_say)
    end
    ngx.exit(500)
end

return _M
