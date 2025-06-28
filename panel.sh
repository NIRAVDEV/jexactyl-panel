#!/bin/bash
set -e

# Update package lists and upgrade the system
apt-get update
apt-get upgrade -y

# Install dependencies
declare -a packages=(
    git \
    curl \
    wget \
    sudo \
    unzip \
    tar \
    software-properties-common \
    mariadb-server \
    redis-server \
    nginx \
    certbot \
    php8.1 \
    php8.1-cli \
    php8.1-fpm \
    php8.1-mysql \
    php8.1-gd \
    php8.1-curl \
    php8.1-zip \
    php8.1-xml \
    php8.1-mbstring \
    php8.1-bcmath \
    php8.1-tokenizer \
    php8.1-opcache
)
apt-get install -y ${packages[@]}

# Install Composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('composer-setup.php');"

# Configure Nginx
rm /etc/nginx/sites-available/default
rm /etc/nginx/sites-enabled/default

cat <<EOF >/etc/nginx/sites-available/jexactyl.conf
server {
    listen 80;
    server_name _; # Replace with your domain or IP address
    root /var/www/jexactyl/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/jexactyl.conf /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Secure Nginx with Certbot (optional, but recommended)
# certbot --nginx -d your_domain.com # Replace your_domain.com

# Set up MariaDB database and user
MYSQL_ROOT_PASSWORD="rootpassword"
MYSQL_DATABASE="jexactyl"
MYSQL_USER="jexactyl"
MYSQL_PASSWORD="jexactylpassword"

export DEBIAN_FRONTEND=noninteractive

# Note: This is insecure.  For production, use a more robust method for setting MySQL password.
# Also, be sure to change the root password

cat <<EOF | mysql -u root
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DROP DATABASE IF EXISTS 
CREATE DATABASE IF NOT EXISTS 
CREATE USER IF NOT EXISTS '
GRANT ALL PRIVILEGES ON 
FLUSH PRIVILEGES;
EOF

# Download Jexactyl
cd /var/www
git clone https://github.com/Jexactyl/Jexactyl.git
cd jexactyl

# Install PHP dependencies
composer install --no-dev --optimize-autoloader

# Set up environment variables
cp .env.example .env

# Generate application key
php artisan key:generate

# Jexactyl Setup Commands (Interactive)
php artisan p:environment:setup -f
php artisan p:environment:database -f
php artisan p:environment:mail -f
php artisan p:environment:admin -f


# Database setup (Uncomment the below lines to perform migrations and seeders)
php artisan migrate --seed


# Set correct file permissions
chown -R www-data:www-data /var/www/jexactyl
chmod -R 755 /var/www/jexactyl/storage
chmod -R 755 /var/www/jexactyl/bootstrap/cache

# Create systemd service for the queue worker
cat <<EOF >/etc/systemd/system/pteroq.service
[Unit]
Description=Jexactyl Queue Worker
After=redis-server.service mariadb.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/jexactyl
ExecStart=php artisan queue:work --queue=high,default
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable pteroq
systemctl start pteroq

# Restart services
systemctl restart redis
systemctl restart mariadb
systemctl restart nginx

# Post-installation message
cat <<EOF
+-----------------------------------------------------------------------+
|                                                                       |
|                       Jexactyl Installation Complete!                 |
|                                                                       |
|  Next Steps:                                                          |
|                                                                       |
|  1. Create an administrator account by running:                       |
|     php artisan p:user:make                                           |
|     in the /var/www/jexactyl directory.                               |
|                                                                       |
|  2. Access the panel in your browser at your server's IP address.    |
|                                                                       |
+-----------------------------------------------------------------------+
EOF
