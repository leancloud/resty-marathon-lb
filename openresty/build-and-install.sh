#!/bin/bash
set -e

TMP_FILES=$(mktemp)
CPU_COUNT=$([[ $(uname) = 'Darwin' ]] && sysctl -n hw.logicalcpu_max || lscpu -p | egrep -v '^#' | wc -l)

function tmpfile {
  local filename=$(mktemp $@)
  echo $filename >> $TMP_FILES
  echo $filename
}

CONFIGURE_EXTRAS=$(tmpfile)
LD_OPT_EXTRAS=$(tmpfile)
LD_OPT_RPATH=$(tmpfile -d)
ENV_EXTRAS=$(tmpfile)
BUILD_TMP=$(tmpfile -d)

CWD="$(pwd)"

# Functions
function append_configure_extras {
  echo $@ >> ${CONFIGURE_EXTRAS}
}

function append_ld_opt_extras {
  echo $@ >> ${LD_OPT_EXTRAS}
}

function append_env_extras {
  echo "export $@" >> ${ENV_EXTRAS}
}

function append_ld_rpath {
  find $(realpath "$1") -type f -print | \
  xargs -I {} sh -c "cp \"\$1\" ${LD_OPT_RPATH}/\$(basename \"\$1\")" - {}

  find -L $(realpath "$1") -xtype l -print | \
  xargs -I {} sh -c "cp \"\$1\" ${LD_OPT_RPATH}/\$(basename \"\$1\")" - {}
}

source cfg/versions

# Download OpenResty
OPENRESTY_TAR="openresty-${OPENRESTY_VERSION}.tar.gz"
OPENRESTY_URL="https://openresty.org/download/{$OPENRESTY_TAR}"
OPENRESTY_DIR="openresty-${OPENRESTY_VERSION}"

if [ ! -d "${OPENRESTY_DIR}" ]; then
    wget -O "${OPENRESTY_TAR}" "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz"
    tar -zxf "${OPENRESTY_TAR}"
fi

# Download OpenSSL
if [ "$OPENSSL_VERSION" != "" ]; then
  OPENSSL_TAR="openssl-${OPENSSL_VERSION}.tar.gz"
  OPENSSL_URL="https://www.openssl.org/source/${OPENSSL_TAR}"
  OPENSSL_DIR="openssl-${OPENSSL_VERSION}"

  if [ ! -d "${OPENSSL_DIR}" ]; then
    wget -O "${OPENSSL_TAR}" "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
    tar -zxf "${OPENSSL_TAR}"
    pushd "${OPENSSL_DIR}"
    patch -p1 < "../${OPENRESTY_DIR}/patches/openssl-1.0.2h-sess_set_get_cb_yield.patch"
    popd
  fi

  append_configure_extras --with-openssl="../${OPENSSL_DIR}"
fi

# Download PCRE
if [ "$PCRE_VERSION" != "" ]; then
  PCRE_TAR="pcre-${PCRE_VERSION}.tar.gz"
  PCRE_URL="https://ftp.pcre.org/pub/pcre/${PCRE_TAR}"
  PCRE_DIR="pcre-${PCRE_VERSION}"

  if [ ! -d "${PCRE_DIR}" ]; then
    wget -O "${PCRE_TAR}" "${PCRE_URL}"
    tar -zxf "${PCRE_TAR}"
    pushd "${PCRE_DIR}"
    popd
  fi

  append_configure_extras --with-pcre="../${PCRE_DIR}" --with-pcre-jit
fi

# Build Modules
function download-module {
  [ -d "mods/${1}" ] && return
  rm -rf "mods/${1}"
  git clone --recursive "${2}" "mods/${1}"
  pushd "mods/${1}"
  git checkout "${3}"
  git submodule update --init --recursive
  popd
}

function build-static-module {
  download-module $@
  append_configure_extras --add-module="../mods/${1}"
}

mkdir -p mods
source cfg/modules

# Build OpenResty
pushd "${OPENRESTY_DIR}"
./configure \
  --with-ipv6 \
  --with-threads --with-file-aio \
  `# nginx http modules and settings ` \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_addition_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_auth_request_module \
  --with-http_geoip_module \
  --with-http_sub_module \
  --with-http_secure_link_module \
  --with-http_degradation_module \
  --with-http_stub_status_module \
  --with-http_slice_module \
  --with-http_flv_module \
  --with-http_mp4_module \
  --with-http_random_index_module \
  `# --with-http_image_filter_module=dynamic` \
  --http-log-path=/var/log/nginx/access.log \
  --http-client-body-temp-path=/var/lib/nginx/body \
  --http-proxy-temp-path=/var/lib/nginx/proxy \
  --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
  --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
  --http-scgi-temp-path=/var/lib/nginx/scgi \
  `# nginx stream modules` \
  --with-stream \
  --with-stream \
  --with-stream_ssl_module \
  `# openresty modules` \
  --with-http_iconv_module \
  --with-luajit \
  `# nginx settings` \
  --prefix=/usr/share/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --lock-path=/var/lock/nginx.lock \
  --pid-path=/run/nginx.pid \
  --modules-path=/usr/lib/nginx/modules \
  --user=www-data --group=www-data \
  --build=leanginx-$(date +%Y%m%d) \
  `# build settings` \
  --with-ld-opt="-Wl,-rpath,${LD_OPT_RPATH}" \
  $(cat ${CONFIGURE_EXTRAS})

# Need to static link LuaJIT
mkdir -p libs
append_ld_rpath build/luajit-root/usr/share/nginx/luajit/lib

make "-j${CPU_COUNT}"
make install
popd
