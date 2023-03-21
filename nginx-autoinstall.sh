#!/bin/bash
# shellcheck disable=SC1090,SC2086,SC2034,SC1091,SC2027,SC2206,SC2002

if [[ $EUID -ne 0 ]]; then
	echo -e "Sorry, you need to run this as root"
	exit 1
fi

# Define versions
NGINX_VER=${NGINX_VER:-1.23.3}
OPENSSL_VER=${OPENSSL_VER:-1.1.1t}
HEADERMOD_VER=${HEADERMOD_VER:-0.34}
LIBMAXMINDDB_VER=${LIBMAXMINDDB_VER:-1.7.1}
GEOIP2_VER=${GEOIP2_VER:-3.4}
NGINX_DEV_KIT=${NGINX_DEV_KIT:-0.3.2}
LUA_JIT_VER=${LUA_JIT_VER:-2.1-20230119}
LUA_NGINX_VER=${LUA_NGINX_VER:-0.10.23}
LUA_RESTYCORE_VER=${LUA_RESTYCORE_VER:-0.1.25}
LUA_RESTYLRUCACHE_VER=${LUA_RESTYLRUCACHE_VER:-0.13}
GEOIP2_ACCOUNT_ID=${GEOIP2_ACCOUNT_ID:-842336}
GEOIP2_LICENSE_KEY=${GEOIP2_LICENSE_KEY:-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}

# Define options
NGINX_OPTIONS=${NGINX_OPTIONS:-"
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
	--with-cc-opt=-Wno-deprecated-declarations \
	--with-cc-opt=-Wno-ignored-qualifiers"}
# Define modules
NGINX_MODULES=${NGINX_MODULES:-"--with-compat \
	--with-stream \
	--without-pcre2 \
	--with-http_stub_status_module \
	--with-http_secure_link_module \
	--with-libatomic \
	--with-http_gzip_static_module \
	--with-http_sub_module \
	--with-http_addition_module \
	--with-http_realip_module \
	--with-stream_realip_module \
	--with-stream_ssl_preread_module \
	--with-threads \
	--with-http_ssl_module \
	--with-stream_ssl_module \
	--with-http_v2_module \
	--with-file-aio"}


clear
export DEBIAN_FRONTEND=noninteractive;	

# Cleanup
# The directory should be deleted at the end of the script, but in case it fails
rm -r /usr/local/src/nginx/ >>/dev/null 2>&1
mkdir -p /usr/local/src/nginx/modules


# Dependencies
apt-get update
apt-get install -y build-essential ca-certificates wget curl libpcre3 libpcre3-dev autoconf unzip automake libtool tar git libssl-dev zlib1g-dev uuid-dev lsb-release libxml2-dev libxslt1-dev cmake

	
# GeoIPUpdate
if grep -q "main contrib" /etc/apt/sources.list; then
	echo "main contrib already in sources.list... Skipping"
else
	sed -i "s/main/main contrib/g" /etc/apt/sources.list
fi
sudo add-apt-repository -y ppa:maxmind/ppa
sudo apt update
apt-get install -y geoipupdate


# More Headers
cd /usr/local/src/nginx/modules || exit 1
wget https://github.com/openresty/headers-more-nginx-module/archive/v${HEADERMOD_VER}.tar.gz
tar xaf v${HEADERMOD_VER}.tar.gz


# GeoIP

cd /usr/local/src/nginx/modules || exit 1
# install libmaxminddb
wget https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VER}/libmaxminddb-${LIBMAXMINDDB_VER}.tar.gz
tar xaf libmaxminddb-${LIBMAXMINDDB_VER}.tar.gz
cd libmaxminddb-${LIBMAXMINDDB_VER}/ || exit 1
./configure
make -j "$(nproc)"
make install
ldconfig

cd ../ || exit 1
wget https://github.com/leev/ngx_http_geoip2_module/archive/${GEOIP2_VER}.tar.gz
tar xaf ${GEOIP2_VER}.tar.gz

mkdir geoip-db
cd geoip-db || exit 1
# - Download GeoLite2 databases using license key
# - Apply the correct, dated filename inside the checksum file to each download instead of a generic filename
# - Perform all checksums
GEOIP2_URLS=( \
	"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key="$GEOIP2_LICENSE_KEY"&suffix=tar.gz" \
	"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key="$GEOIP2_LICENSE_KEY"&suffix=tar.gz" \
	"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key="$GEOIP2_LICENSE_KEY"&suffix=tar.gz" \
)

if [[ ! -d /opt/geoip ]]; then
	for GEOIP2_URL in "${GEOIP2_URLS[@]}"; do
		echo "=== FETCHING ==="
		echo $GEOIP2_URL
		wget -O sha256 "$GEOIP2_URL.sha256"
		GEOIP2_FILENAME=$(cat sha256 | awk '{print $2}')
		mv sha256 "$GEOIP2_FILENAME.sha256"
		wget -O "$GEOIP2_FILENAME" "$GEOIP2_URL"
		echo "=== CHECKSUM ==="
		sha256sum -c "$GEOIP2_FILENAME.sha256"
	done
	tar -xf GeoLite2-ASN_*.tar.gz
	tar -xf GeoLite2-City_*.tar.gz
	tar -xf GeoLite2-Country_*.tar.gz
	mkdir /opt/geoip
	cd GeoLite2-ASN_*/ || exit 1
	mv GeoLite2-ASN.mmdb /opt/geoip/
	cd ../ || exit 1
	cd GeoLite2-City_*/ || exit 1
	mv GeoLite2-City.mmdb /opt/geoip/
	cd ../ || exit 1
	cd GeoLite2-Country_*/ || exit 1
	mv GeoLite2-Country.mmdb /opt/geoip/
else
	echo -e "GeoLite2 database files exists... Skipping download"
fi

# Download GeoIP.conf for use with geoipupdate
if [[ ! -f /usr/local/etc/GeoIP.conf ]]; then
	cd /usr/local/etc || exit 1
	wget https://raw.githubusercontent.com/vovler/nginx-autoinstall/master/conf/GeoIP.conf
	sed -i "s/YOUR_ACCOUNT_ID_HERE/${GEOIP2_ACCOUNT_ID}/g" GeoIP.conf
	sed -i "s/YOUR_LICENSE_KEY_HERE/${GEOIP2_LICENSE_KEY}/g" GeoIP.conf
else
	echo -e "GeoIP.conf file exists... Skipping"
fi
	
if [[ ! -f /etc/cron.d/geoipupdate ]]; then
	# Install crontab to run twice a week
	echo -e "40 23 * * 6,3 /usr/local/bin/geoipupdate" > /etc/cron.d/geoipupdate
else
	echo -e "geoipupdate crontab file exists... Skipping"
fi


# Cache Purge
cd /usr/local/src/nginx/modules || exit 1
git clone --depth 1 https://github.com/nginx-modules/ngx_cache_purge

	
# Lua
# LuaJIT download
cd /usr/local/src/nginx/modules || exit 1
wget https://github.com/openresty/luajit2/archive/v${LUA_JIT_VER}.tar.gz
tar xaf v${LUA_JIT_VER}.tar.gz
cd luajit2-${LUA_JIT_VER} || exit 1
make -j "$(nproc)"
make install

# ngx_devel_kit download
cd /usr/local/src/nginx/modules || exit 1
wget https://github.com/simplresty/ngx_devel_kit/archive/v${NGINX_DEV_KIT}.tar.gz
tar xaf v${NGINX_DEV_KIT}.tar.gz

# lua-nginx-module download
cd /usr/local/src/nginx/modules || exit 1
wget https://github.com/openresty/lua-nginx-module/archive/v${LUA_NGINX_VER}.tar.gz
tar xaf v${LUA_NGINX_VER}.tar.gz

# lua-resty-core download
cd /usr/local/src/nginx/modules || exit 1
wget https://github.com/openresty/lua-resty-core/archive/v${LUA_RESTYCORE_VER}.tar.gz
tar xaf v${LUA_RESTYCORE_VER}.tar.gz
cd lua-resty-core-${LUA_RESTYCORE_VER} || exit 1
make install PREFIX=/etc/nginx

# lua-resty-lrucache download
cd /usr/local/src/nginx/modules || exit 1
wget https://github.com/openresty/lua-resty-lrucache/archive/v${LUA_RESTYLRUCACHE_VER}.tar.gz
tar xaf v${LUA_RESTYLRUCACHE_VER}.tar.gz
cd lua-resty-lrucache-${LUA_RESTYLRUCACHE_VER} || exit 1
make install PREFIX=/etc/nginx


# OpenSSL
cd /usr/local/src/nginx/modules || exit 1
wget https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz
tar xaf openssl-${OPENSSL_VER}.tar.gz
cd openssl-${OPENSSL_VER} || exit 1
./config


# Download and extract of Nginx source code
cd /usr/local/src/nginx/ || exit 1
wget -qO- http://nginx.org/download/nginx-${NGINX_VER}.tar.gz | tar zxf -
cd nginx-${NGINX_VER} || exit 1


# As the default nginx.conf does not work, we download a clean and working conf from my GitHub.
# We do it only if it does not already exist, so that it is not overriten if Nginx is being updated
if [[ ! -e /etc/nginx/nginx.conf ]]; then
	mkdir -p /etc/nginx
	cd /etc/nginx || exit 1
	wget https://raw.githubusercontent.com/vovler/nginx-autoinstall/master/conf/nginx.conf
fi
cd /usr/local/src/nginx/nginx-${NGINX_VER} || exit 1


# Optional options
NGINX_OPTIONS=$(
	echo " $NGINX_OPTIONS"
	echo --with-ld-opt="-Wl,-rpath,/usr/local/lib/"
)


NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo "--add-module=/usr/local/src/nginx/modules/headers-more-nginx-module-${HEADERMOD_VER}"
)


NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo "--add-module=/usr/local/src/nginx/modules/ngx_http_geoip2_module-${GEOIP2_VER}"
)


NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo "--with-openssl=/usr/local/src/nginx/modules/openssl-${OPENSSL_VER}"
)


NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo "--add-module=/usr/local/src/nginx/modules/ngx_cache_purge"
)


NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo "--add-module=/usr/local/src/nginx/modules/ngx_devel_kit-${NGINX_DEV_KIT}"
)
	
NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo "--add-module=/usr/local/src/nginx/modules/lua-nginx-module-${LUA_NGINX_VER}"
)

	
git clone --depth 1 --quiet https://github.com/openresty/set-misc-nginx-module.git /usr/local/src/nginx/modules/set-misc-nginx-module

NGINX_MODULES=$(
	echo "$NGINX_MODULES"
	echo --add-module=/usr/local/src/nginx/modules/set-misc-nginx-module
)
	

# Cloudflare's TLS Dynamic Record Resizing patch
wget https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.17.7%2B.patch -O tcp-tls.patch
patch -p1 <tcp-tls.patch


# Cloudflare's Cloudflare's full HPACK encoding patch
wget https://raw.githubusercontent.com/hakasenyang/openssl-patch/master/nginx_hpack_push_1.15.3.patch -O nginx_http2_hpack.patch
patch -p1 <nginx_http2_hpack.patch

NGINX_OPTIONS=$(
	echo "$NGINX_OPTIONS"
	echo --with-http_v2_hpack_enc
)

export LUAJIT_LIB=/usr/local/lib/
export LUAJIT_INC=/usr/local/include/luajit-2.1/


./configure $NGINX_OPTIONS $NGINX_MODULES
make -j "$(nproc)"
make install

# remove debugging symbols
strip -s /usr/sbin/nginx

# Nginx installation from source does not add an init script for systemd and logrotate
# Using the official systemd script and logrotate conf from nginx.org
if [[ ! -e /lib/systemd/system/nginx.service ]]; then
	cd /lib/systemd/system/ || exit 1
	wget https://raw.githubusercontent.com/vovler/nginx-autoinstall/master/conf/nginx.service
	# Enable nginx start at boot
	systemctl enable nginx
fi

if [[ ! -e /etc/logrotate.d/nginx ]]; then
	cd /etc/logrotate.d/ || exit 1
	wget https://raw.githubusercontent.com/vovler/nginx-autoinstall/master/conf/nginx-logrotate -O nginx
fi

# Nginx's cache directory is not created by default
if [[ ! -d /var/cache/nginx ]]; then
	mkdir -p /var/cache/nginx
fi

# We add the sites-* folders as some use them.
if [[ ! -d /etc/nginx/sites-available ]]; then
	mkdir -p /etc/nginx/sites-available
fi
if [[ ! -d /etc/nginx/sites-enabled ]]; then
	mkdir -p /etc/nginx/sites-enabled
fi
if [[ ! -d /etc/nginx/conf.d ]]; then
	mkdir -p /etc/nginx/conf.d
fi
if [[ -d /etc/nginx/conf.d ]]; then
	# add necessary `lua_package_path` directive to `nginx.conf`, in the http context
	echo -e 'lua_package_path "/etc/nginx/lib/lua/?.lua;;";' >/etc/nginx/conf.d/lua_package_path.conf
fi
# Restart Nginx
systemctl restart nginx

# Block Nginx from being installed via APT
if [[ $(lsb_release -si) == "Debian" ]] || [[ $(lsb_release -si) == "Ubuntu" ]]; then
	cd /etc/apt/preferences.d/ || exit 1
	echo -e 'Package: nginx*\nPin: release *\nPin-Priority: -1' >nginx-block
fi

# Removing temporary Nginx and modules files
rm -r /usr/local/src/nginx

# We're done !
echo "Installation done."
exit
