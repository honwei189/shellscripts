#!/bin/sh
###
 # @description       : Install NGINX with HTTP 2 and GeoIP databases
 # @version           : "1.0.0" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 03/04/2020 10:07:08
 # @last modified     : 09/03/2022 09:04:31
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###

dnf remove nginx -y

getent passwd nginx > /dev/null 2&>1

if [ ! $? -eq 0 ]; then
    useradd nginx
fi

#Generate SSL cert
curl -L https://github.com/honwei189/shellscripts/raw/master/utilities/gen_cert.sh |sh

#Install necessary library for nginx (http2)
dnf -y install libxml2 libxml2-dev
dnf -y install libxslt-devel

#Install via use yum if libxml2-dev not found
yum -y install libxml2-devel

#Install library for nginx (HTTP image filter module requires the GD library)
dnf -y install gd-devel


#Install library for nginx (perl module ExtUtils::Embed is required)
dnf -y install perl-devel perl-ExtUtils-Embed

mkdir -p /usr/local/src/nginx/modules/

cd /usr/local/src/nginx/modules/
git clone https://github.com/leev/ngx_http_geoip2_module.git

cd /usr/local/src/

#Download GeoLite library
#git clone --recursive https://github.com/maxmind/libmaxminddb
#cd libmaxminddb/
#./bootstrap

wget https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz
tar xvfz libmaxminddb-1.6.0.tar.gz
cd libmaxminddb-1.6.0
./configure
make
make check
make install
ldconfig



dnf install geoipupdate -y
dnf install https://github.com/maxmind/geoipupdate/releases/download/v4.9.0/geoipupdate_4.9.0_linux_amd64.rpm -y



mkdir -p /usr/local/src/nginx/modules/
cd /usr/local/src/nginx/modules/
git clone https://github.com/openresty/headers-more-nginx-module.git
git clone https://github.com/google/ngx_brotli.git
git clone --recursive https://github.com/cloudflare/quiche
git clone https://github.com/leev/ngx_http_geoip2_module.git



cd /usr/local/src/
wget https://www.openssl.org/source/openssl-1.1.1m.tar.gz
tar -zxf openssl-1.1.1m.tar.gz
cd openssl-1.1.1m
./config

make
#make install




cd /usr/local/src/
#wget ftp://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz
wget https://github.com/PhilipHazel/pcre2/releases/download/pcre2-10.39/pcre2-10.39.tar.gz
tar -zxf pcre2-10.39.tar.gz
cd pcre2-10.39
#./configure
./configure --prefix=/usr --libdir=/usr/lib64 --enable-unicode-properties --enable-pcre16 --enable-pcre32 --enable-pcregrep-libz --disable-static --enable-utf8 --enable-shared
make
#make install




cd /usr/local/src/nginx/modules/
wget https://openresty.org/download/openresty-1.19.9.1.tar.gz
tar -xzvf openresty-1.19.9.1.tar.gz
cd openresty-1.19.9.1
#./configure --prefix=/opt/openresty \
#            --with-luajit \
#            --without-http_redis2_module \
#            --with-http_iconv_module \
#            --with-pcre-jit \
#            --with-cc-opt="-I/usr/local/opt/openssl/include/ -I/usr/local/opt/pcre/include/" \
#            --with-ld-opt="-L/usr/local/opt/openssl/lib/ -L/usr/local/opt/pcre/lib/" \
#            -j8

./configure --with-luajit \
            --without-http_redis2_module \
            --with-http_iconv_module \
            --with-pcre-jit \
            --with-openssl=/usr/local/src/openssl-1.1.1m \
            --with-pcre=/usr/local/src/pcre2-10.39 -j4
            
make -j2
#make install


# better also add the following line to your ~/.bashrc or ~/.bash_profile file.
export PATH=/usr/local/openresty/bin:$PATH



cd /usr/local/src
wget http://zlib.net/zlib-1.2.11.tar.gz
tar -zxf zlib-1.2.11.tar.gz
cd zlib-1.2.11
./configure
make
#make install




cd /usr/local/src/
curl -O http://nginx.org/download/nginx-1.21.6.tar.gz
tar xvzf nginx-1.21.6.tar.gz
ln -s /usr/lib64/nginx/modules /etc/nginx/
cd /usr/local/src/nginx/modules/ngx_brotli && git submodule update --init && cd /usr/local/src/nginx-1.21.6
mkdir -p /var/cache/nginx/client_temp
mkdir -p /etc/nginx


./configure \
--prefix=/etc/nginx \
--sbin-path=/usr/sbin/nginx \
--modules-path=/usr/lib64/nginx/modules \
--conf-path=/etc/nginx/nginx.conf \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--pid-path=/var/run/nginx.pid \
--lock-path=/var/run/nginx.lock \
--http-client-body-temp-path=/var/cache/nginx/client_temp \
--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
--user=nginx \
--group=nginx \
--with-file-aio \
--with-http_ssl_module \
--with-http_v2_module \
--with-http_realip_module \
--with-http_addition_module \
--with-http_xslt_module=dynamic \
--with-http_image_filter_module=dynamic \
--with-http_sub_module \
--with-http_dav_module \
--with-http_flv_module \
--with-http_mp4_module \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_random_index_module \
--with-http_secure_link_module \
--with-http_degradation_module \
--with-http_slice_module \
--with-http_stub_status_module \
--with-http_perl_module=dynamic \
--with-http_auth_request_module \
--with-mail=dynamic \
--with-mail_ssl_module \
--with-pcre \
--with-pcre-jit \
--with-stream=dynamic \
--with-stream_ssl_module \
--with-debug \
--with-stream_ssl_preread_module \
--with-http_geoip_module \
--add-module=/usr/local/src/nginx/modules/ngx_brotli \
--add-dynamic-module=/usr/local/src/nginx/modules/ngx_http_geoip2_module \
--add-dynamic-module=/usr/local/src/nginx/modules/headers-more-nginx-module

make
make install

ln -s /usr/lib64/nginx/modules /etc/nginx/



# Note: Forwarding request to 'systemctl enable nginx.service'.
# Created symlink from /etc/systemd/system/multi-user.target.wants/nginx.service to /usr/lib/systemd/system/nginx.service.

if [ ! -f "/usr/lib/systemd/system/nginx.service" ]; then
  echo "[Unit]" >> /usr/lib/systemd/system/nginx.service
  echo "Description=nginx - high performance web server" >> /usr/lib/systemd/system/nginx.service
  echo "Documentation=http://nginx.org/en/docs/" >> /usr/lib/systemd/system/nginx.service
  echo "After=network-online.target remote-fs.target nss-lookup.target" >> /usr/lib/systemd/system/nginx.service
  echo "Wants=network-online.target" >> /usr/lib/systemd/system/nginx.service
  echo "" >> /usr/lib/systemd/system/nginx.service
  echo "[Service]" >> /usr/lib/systemd/system/nginx.service
  echo "Type=forking" >> /usr/lib/systemd/system/nginx.service
  echo "PIDFile=/var/run/nginx.pid" >> /usr/lib/systemd/system/nginx.service
  echo "ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx.conf" >> /usr/lib/systemd/system/nginx.service
  echo "ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx.conf" >> /usr/lib/systemd/system/nginx.service
  echo "ExecReload=/bin/kill -s HUP \$MAINPID" >> /usr/lib/systemd/system/nginx.service
  echo "ExecStop=/bin/kill -s TERM \$MAINPID" >> /usr/lib/systemd/system/nginx.service
  echo "" >> /usr/lib/systemd/system/nginx.service
  echo "[Install]" >> /usr/lib/systemd/system/nginx.service
  echo "WantedBy=multi-user.target" >> /usr/lib/systemd/system/nginx.service

  chown -R nginx.nginx /usr/lib/systemd/system/nginx.service && chmod 644 /usr/lib/systemd/system/nginx.service
fi

mkdir -p /var/lib/php/session
mkdir -p /var/lib/php/wsdlcache
chown -R nginx.nginx /var/lib/php/*

mkdir -p /var/cache/nginx/client_temp
chkconfig nginx on


dnf install svn -y

cd ~/
svn export "$(sed 's/tree\/master/trunk/' <<< "https://github.com/honwei189/shellscripts/tree/master/etc/nginx")"
cp -Rp /etc/nginx /root/nginx_bak
yes | cp -Rp nginx /etc/
rm -rf nginx


##########

if [ ! -z "$(type -P geoipupdate)" ]
then
  if [ -f /etc/GeoIP.conf ] && [ ! -z "$(cat GeoIP.conf | grep 'AccountID YOUR_ACCOUNT_ID_HERE')" ]; then
    echo "####### GeoIP #######"
    echo ""
    echo "If you doesn't have an account from MaxMind (GeoIP), please go to following website to register and create a licence key"
    echo ""
    echo "https://www.maxmind.com/en/geolite2/signup"
    echo ""
    echo -n "Enter your AccountID and press [ENTER]: "
    read var_geoaccountid

    if [ "$var_geoaccountid" == "" ]
    then
        echo "Skip ..."
    else
        sed -i 's/AccountID YOUR_ACCOUNT_ID_HERE/AccountID '$var_geoaccountid'/g' /etc/GeoIP.conf

        echo -n "Enter your licence key and press [ENTER]: "
        read var_geolicencekey

        if [ ! -z "$var_geolicencekey" ]
        then
            sed -i 's/LicenseKey YOUR_LICENSE_KEY_HERE/LicenseKey '$var_geolicencekey'/g' /etc/GeoIP.conf
        else
            echo "Skip ..."
        fi
    fi
  fi

  geoipupdate

fi

