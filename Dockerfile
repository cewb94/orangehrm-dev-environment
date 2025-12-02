########################################
# 1) Frontend builder (Vue / Yarn)
########################################
FROM node:18-bullseye AS frontend-builder

WORKDIR /app

# Copy all source code into builder container
COPY . .

# Install dos2unix for CRLF → LF conversion
RUN apt-get update \
 && apt-get install -y dos2unix \
 && rm -rf /var/lib/apt/lists/*

# Enable Yarn via corepack
RUN corepack enable

# Normalize Windows newlines
RUN find src/client -type f \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.json' \) -print0 \
      | xargs -0 dos2unix \
 && find installer/client -type f \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.json' \) -print0 \
      | xargs -0 dos2unix

# Build main SPA
RUN cd src/client \
 && yarn install \
 && yarn build

# Build installer SPA
RUN cd installer/client \
 && yarn install \
 && yarn build


########################################
# 2) PHP 8.3 Apache runtime
########################################
FROM php:8.3-apache

ENV DEBIAN_FRONTEND=noninteractive

# Install system libs + PHP extensions
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      unzip \
      libicu-dev \
      libxml2-dev \
      libpng-dev \
      libonig-dev \
      libzip-dev \
      libldap2-dev \
 && docker-php-ext-configure intl \
 && docker-php-ext-configure ldap --with-ldap=/usr \
 && docker-php-ext-install intl pdo_mysql gd zip ldap \
 && docker-php-ext-enable opcache \
 && a2enmod rewrite ssl headers \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# Copy built result from Node builder
COPY --from=frontend-builder /app /var/www/html

# Fix git-safe-directory so Composer works
RUN git config --global --add safe.directory /var/www/html

# Install Composer
RUN curl -sS https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer

# Install PHP dependencies
RUN composer install -d src --no-dev --optimize-autoloader \
 && composer dump-autoload -d src --optimize

# Fix permissions for installer writable directories
# These MUST stay inside the image because they are later replaced by named volumes
RUN mkdir -p /var/www/html/lib/confs \
 && mkdir -p /var/www/html/src/cache \
 && mkdir -p /var/www/html/src/log \
 && chown -R www-data:www-data /var/www/html/lib/confs /var/www/html/src/cache /var/www/html/src/log \
 && chmod -R 775 /var/www/html/lib/confs /var/www/html/src/cache /var/www/html/src/log

