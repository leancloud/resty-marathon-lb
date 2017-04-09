#!/bin/bash

set -x -e

TMP=$(mktemp -d /tmp/docker_build.XXXXXXXX)

TIMEZONE=${TIMEZONE:-Asia/Shanghai}
UBUNTU_MIRROR=${UBUNTU_MIRROR:-archive.ubuntu.com}
REGISTRY=${REGISTRY:-docker-registry:5000}

cp -r * $TMP/

cat <<EOF > $TMP/Dockerfile
FROM ubuntu:16.04
MAINTAINER bwang@leancloud.rocks

ENV TERM xterm
RUN echo "$TIMEZONE" | tee /etc/timezone
RUN dpkg-reconfigure --frontend noninteractive tzdata
RUN useradd --create-home ubuntu
RUN locale-gen zh_CN.UTF-8
WORKDIR /tmp/docker-build
RUN sed -i 's/archive.ubuntu.com/$UBUNTU_MIRROR/g' /etc/apt/sources.list
RUN apt-get update && apt-get install -y sudo autoconf build-essential curl dnsutils gettext git libgeoip-dev libncurses5-dev libpcre3-dev libreadline-dev libtool netcat python-pip realpath supervisor telnet vim wget zlib1g-dev
RUN pip install ngxtop
ADD openresty /tmp/docker-build/openresty
RUN cd openresty && ./build-and-install.sh
WORKDIR /home/ubuntu
ADD conf /home/ubuntu/conf
ADD launcher.sh /home/ubuntu/launcher.sh
CMD ["/home/ubuntu/launcher.sh"]
EOF

pushd $TMP

APP=leanginx

DOCKER_TAG=$APP:$(date +%Y%m%d%H%M%S)
TAG_FILE=${TAG_FILE:-/tmp/tag-$APP}

rm -f $TAG_FILE

sudo docker build -t $REGISTRY/$DOCKER_TAG .
sudo docker push $REGISTRY/$DOCKER_TAG
echo $REGISTRY/$DOCKER_TAG > $TAG_FILE
