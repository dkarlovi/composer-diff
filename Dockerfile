ARG COMPOSER_DOCKER_IMAGE=composer/composer:2.8.8-bin
ARG PHP_DOCKER_IMAGE=php:8.4.6-cli-alpine
ARG PHP_BRANCH=8.4.6

FROM emscripten/emsdk:3.1.35 AS sdk
RUN apt-get update && \
  apt-get --no-install-recommends -y install \
    build-essential \
    automake \
    autoconf \
    libtool \
    pkgconf \
    bison \
    flex \
    re2c \
    gdb \
    libxml2-dev \
    pv \
    re2c

FROM sdk AS php-src
ARG PHP_BRANCH
RUN git clone https://github.com/php/php-src.git php-src \
        --branch PHP-$PHP_BRANCH \
        --single-branch \
        --depth 1

FROM php-src AS php-bin
ARG WASM_ENVIRONMENT=web
ARG JAVASCRIPT_EXTENSION=mjs
ARG EXPORT_NAME=createPhpModule
ARG MODULARIZE=1
ARG EXPORT_ES6=1
ARG ASSERTIONS=0
ARG OPTIMIZE=-O1
# TODO: find a way to keep this, it can't be empty if defined...
# ARG PRE_JS=
ARG INITIAL_MEMORY=256mb
RUN cd /src/php-src \
    && ./buildconf --force \
    && emconfigure ./configure \
        --with-config-file-scan-dir=/src/php \
        --with-layout=GNU \
        --enable-embed=static \
        --enable-ctype \
        --enable-filter \
        --enable-json \
        --enable-mbstring \
        --enable-session \
        --enable-tokenizer \
        --enable-posix \
        --disable-all \
        --disable-cgi \
        --disable-cli \
        --disable-fiber-asm \
        --disable-mbregex \
        --disable-rpath \
        --disable-phpdbg \
        --without-pcre-jit \
        --without-pear \
        --with-valgrind=no
RUN cd /src/php-src && emmake make -j8 
RUN cd /src/php-src && bash -c '[[ -f .libs/libphp7.la ]] && mv .libs/libphp7.la .libs/libphp.la && mv .libs/libphp7.a .libs/libphp.a && mv .libs/libphp7.lai .libs/libphp.lai || exit 0'
# TODO: this could be a shim directly in the Dockerfile
COPY ./source /src/source
RUN cd /src/php-src && emcc $OPTIMIZE \
        -I .     \
        -I Zend  \
        -I main  \
        -I TSRM/ \
        -c /src/source/phpw.c \
        -o /src/phpw.o \
        -s ERROR_ON_UNDEFINED_SYMBOLS=0

FROM ${COMPOSER_DOCKER_IMAGE} AS composer

FROM ${PHP_DOCKER_IMAGE} AS php-deps
COPY --from=composer /composer /usr/bin/composer
COPY composer.* /app/
RUN --mount=type=cache,target=/composer COMPOSER_HOME=/composer cd /app && /usr/bin/composer install --no-autoloader --no-dev --no-interaction --no-scripts --prefer-dist
COPY ./src /app/src
COPY ./data /app/data
COPY ./templates /app/templates
COPY ./public/index.php /app/public/index.php
RUN --mount=type=cache,target=/composer COMPOSER_HOME=/composer cd /app && /usr/bin/composer dump-autoload --classmap-authoritative

FROM php-bin AS php-wasm
COPY --from=php-deps /app /app
RUN mkdir /build && cd /src/php-src && emcc $OPTIMIZE \
    -o /build/app-$WASM_ENVIRONMENT.$JAVASCRIPT_EXTENSION \
    -gseparate-dwarf=/build/app-$WASM_ENVIRONMENT.debug.wasm \
    -s EXPORTED_FUNCTIONS='["_phpw_with_args"]' \
    -s EXTRA_EXPORTED_RUNTIME_METHODS='["ccall", "UTF8ToString", "lengthBytesUTF8", "FS"]' \
    -s ENVIRONMENT=$WASM_ENVIRONMENT    \
    -s FORCE_FILESYSTEM=1            \
    -s MAXIMUM_MEMORY=2gb             \
    -s INITIAL_MEMORY=$INITIAL_MEMORY \
    -s ALLOW_MEMORY_GROWTH=1         \
    -s ASSERTIONS=$ASSERTIONS      \
    -s ERROR_ON_UNDEFINED_SYMBOLS=0  \
    -s MODULARIZE=$MODULARIZE        \
    -s INVOKE_RUN=0                  \
    -s LZ4=1                  \
    -s EXPORT_ES6=$EXPORT_ES6 \
    -s EXPORT_NAME=$EXPORT_NAME \
    # -s DECLARE_ASM_MODULE_EXPORTS=0 \
    --embed-file /app@/app \
    -lidbfs.js                       \
        /src/phpw.o .libs/libphp.a
RUN rm -r /src/*

FROM scratch
COPY --from=php-wasm /build/ app/
