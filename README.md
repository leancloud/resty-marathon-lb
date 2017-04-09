# resty-marathon-lb

## 这是啥玩意

这是一个 LeanCloud 维护的基于 OpenResty 的服务发现路由。
在 nginx 配置里说明要 proxy_pass 的 Marathon 应用，就可以直接路由过去了。

```nginx
server {
    listen 80;
    server_name example.com;
    location / {
        dyups_interface;
        # "marathon-rest-api地址#应用id:应用端口"
        set $marathon_app "marathon:8080#your-awesome-app:4000";
        set $upstream "";
        access_by_lua_file "lua/marathon-app.lua";
        proxy_pass http://$upstream;
    }
}
```

```bash
$ curl http://example.com/ping
This is your awesome app serving at port 23745 (a Mesos allocated port)
```

## 怎么用

看看 `nginx.conf` 和 `components.conf`。
通过 `build.sh` 可以构建出一个 docker 镜像，用这个部署就可以了。
可以直接用 `--net=host` 来部署，会暴露4个端口：
- 80 HTTP
- 880 接受 Proxy Protocol 的 HTTP
- 443 HTTPS
- 8443 接受 Proxy Protocol 的 HTTPS

## License
MIT
