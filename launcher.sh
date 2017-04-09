#!/bin/bash

rm -rf /var/{log,lib}/nginx
mkdir /var/{log,lib}/nginx /var/log/nginx/leanapp
chown -R ubuntu:ubuntu /var/{log,lib}/nginx

cat <<EOF > conf/resolver.conf
resolver $(grep ^nameserver /etc/resolv.conf | awk '{print $2}' | xargs);
EOF

cat <<EOF > supervisord.conf
[supervisord]
logfile=${MESOS_SANDBOX:-/tmp}/supervisord.log
childlogdir=${MESOS_SANDBOX:-/tmp}

[unix_http_server]
file=/var/run//supervisor.sock
chmod=0770
chown=root:root

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run//supervisor.sock

[program:nginx]
command = /usr/sbin/nginx -p /home/ubuntu/conf -c nginx.conf
user = root
autostart = true
autorestart = true
EOF

exec supervisord -n -c supervisord.conf
