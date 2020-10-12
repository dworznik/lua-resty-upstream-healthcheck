FROM ubuntu:trusty

ENV JOBS=3
ENV NGX_BUILD_JOBS=$JOBS
ENV LUAJIT_PREFIX=/usr/local
ENV LUAJIT_LIB=$LUAJIT_PREFIX/lib
ENV LUAJIT_INC=$LUAJIT_PREFIX/include/luajit-2.1
ENV LUA_INCLUDE_DIR=$LUAJIT_INC
ENV LUA_CMODULE_DIR=/lib
ENV OPENSSL_PREFIX=/usr/src/ssl
ENV OPENSSL_LIB=$OPENSSL_PREFIX/lib
ENV OPENSSL_INC=$OPENSSL_PREFIX/include
ENV OPENSSL_VER=1.0.2j
ENV LD_LIBRARY_PATH=$LUAJIT_LIB:$LD_LIBRARY_PATH
ENV TEST_NGINX_SLEEP=0.006
ENV CC=gcc
ENV NGINX_VERSION=1.19.3

#RUN apk --no-cache add perl perl-dev wget perl-app-cpanminus git
RUN apt-get update -y
RUN apt-get install -y build-essential git zlib1g-dev libpcre3 libpcre3-dev libbz2-dev wget cpanminus axel

RUN cpanm --notest Test::Nginx > build.log 2>&1 || (cat build.log && exit 1)

WORKDIR /usr/src

RUN if [ ! -d download-cache ]; then mkdir download-cache; fi
RUN if [ ! -f download-cache/openssl-$OPENSSL_VER.tar.gz ]; then wget -O download-cache/openssl-$OPENSSL_VER.tar.gz https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz; fi

RUN git clone --depth 1 https://github.com/openresty/openresty.git ../openresty
RUN git clone --depth 1 https://github.com/openresty/nginx-devel-utils.git
RUN git clone --depth 1 https://github.com/simpl/ngx_devel_kit.git ../ndk-nginx-module
RUN git clone --depth 1 https://github.com/openresty/lua-nginx-module.git ../lua-nginx-module
RUN git clone --depth 1 https://github.com/openresty/lua-resty-core.git ../lua-resty-core
RUN git clone --depth 1 https://github.com/openresty/lua-resty-lrucache.git ../lua-resty-lrucache
RUN git clone --depth 1 https://github.com/openresty/lua-upstream-nginx-module.git ../lua-upstream-nginx-module
RUN git clone --depth 1 https://github.com/openresty/echo-nginx-module.git ../echo-nginx-module
RUN git clone --depth 1 https://github.com/openresty/no-pool-nginx.git ../no-pool-nginx
RUN git clone -b v2.1-agentzh --depth 1 https://github.com/openresty/luajit2.git
RUN git clone --depth 1 https://github.com/openresty/mockeagain.git

WORKDIR /usr/src/luajit2
RUN make -j$JOBS CCDEBUG=-g Q= PREFIX=$LUAJIT_PREFIX CC=$CC XCFLAGS='-DLUA_USE_APICHECK -DLUA_USE_ASSERT' > build.log 2>&1 || (cat build.log && exit 1)
RUN make install PREFIX=$LUAJIT_PREFIX > build.log 2>&1 || (cat build.log && exit 1)

WORKDIR /usr/src
RUN tar zxf download-cache/openssl-$OPENSSL_VER.tar.gz

WORKDIR /usr/src/openssl-$OPENSSL_VER/
RUN ./config shared --prefix=$OPENSSL_PREFIX -DPURIFY > build.log 2>&1 || (cat build.log && exit 1)
RUN make -j$JOBS > build.log 2>&1 || (cat build.log && exit 1)
RUN make PATH=$PATH install_sw > build.log 2>&1 || (cat build.log && exit 1)

WORKDIR /usr/src/mockeagain
RUN make CC=$CC -j$JOBS

WORKDIR /usr/src
ENV PATH=/usr/src/work/nginx/sbin:/usr/src/nginx-devel-utils:$PATH
ENV LD_PRELOAD=/usr/src/mockeagain/mockeagain.so
ENV LD_LIBRARY_PATH=/usr/src/mockeagain:$LD_LIBRARY_PATH
ENV TEST_NGINX_RESOLVER=8.8.4.4
ENV NGX_BUILD_CC=$CC
RUN ngx-build $NGINX_VERSION --with-ipv6 --with-http_realip_module --with-http_ssl_module --with-cc-opt="-I$OPENSSL_INC" --with-ld-opt="-L$OPENSSL_LIB -Wl,-rpath,$OPENSSL_LIB" --add-module=/usr/ndk-nginx-module --add-module=/usr/lua-nginx-module --add-module=/usr/lua-upstream-nginx-module --add-module=/usr/echo-nginx-module --with-debug > build.log 2>&1 || (cat build.log && exit 1)
RUN nginx -V
RUN ldd `which nginx`|grep -E 'luajit|ssl|pcre'


ENV OPENRESTY_PREFIX=/usr/src/work
ENV LUA_LIB_DIR=/usr/local/share/lua/5.1

WORKDIR /usr/lua-resty-lrucache
RUN make install

WORKDIR /usr/lua-resty-core
RUN make install

WORKDIR /usr/src
RUN git clone --depth 1 https://github.com/openresty/lua-cjson ../lua-cjson
WORKDIR /usr/lua-cjson
RUN DESTDIR=/usr/src make install

WORKDIR /usr/src
ADD t/lib/ t/lib/
ADD t/sanity.t t/sanity.t
ADD lib/ lib/
ADD Makefile .
RUN make install
CMD make test
