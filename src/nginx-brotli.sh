#!/bin/bash
NGINX_VER=$(curl -s https://raw.githubusercontent.com/Angristan/nginx-autoinstall/master/var/nginx)
apt-get install build-essential ca-certificates curl libpcre3 libpcre3-dev autoconf automake libtool tar git libssl-dev -y
cd /opt
rm -r libbrotli
git clone https://github.com/bagder/libbrotli
cd libbrotli
./autogen.sh
./configure
make -j $(nproc)
make install
ldconfig
cd /opt
git clone https://github.com/google/ngx_brotli
rm -r /opt/nginx-${NGINX_VER}
wget -qO- http://nginx.org/download/nginx-${NGINX_VER}.tar.gz | tar zxf -
cd nginx-${NGINX_VER}
./configure \
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--user=nginx \
	--group=nginx \
	--without-http_ssi_module \
	--without-http_scgi_module \
	--without-http_uwsgi_module \
	--without-http_geo_module \
	--without-http_map_module \
	--without-http_split_clients_module \
	--without-http_memcached_module \
	--without-http_empty_gif_module \
	--without-http_browser_module \
	--with-threads \
	--with-file-aio \
	--with-http_ssl_module \
	--with-http_v2_module \
	--with-ipv6 \
	--with-http_mp4_module \
	--with-http_auth_request_module \
	--with-http_slice_module \
	--add-module=/opt/ngx_brotli
make -j $(nproc)
make install
