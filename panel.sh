#!/bin/bash
set -e

# Update package lists and upgrade the system
apt-get update
apt-get upgrade -y

# Install required dependencies
apt-get install -y git curl wget sudo unzip tar software-properties-common mariadb-server redis nginx certbot php php-cli php-fpm php-mysql php-gd php-curl php-zip php-mbstring php-xml php-bcmath

# Set up Nginx configuration for Jexactyl
rm -f /etc/nginx/sites-available/default
rm -f /etc/nginx/sites-enabled/default

cat <<EOF >/etc/nginx/sites-available/jexactyl.conf
server {
    listen 80;
    server_name _; # Replace with your domain or IP address
    root /var/www/jexactyl/public;

    add_header X-Frame-Options "SAMEORIGIN";
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
        fastcgi_pass unix:/run/php/php
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

# Set up MariaDB database and user for Jexactyl
MYSQL_PASSWORD="$(openssl rand -base64 12)"

mariadb -e "CREATE USER 'pterodactyl'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mariadb -e "CREATE DATABASE IF NOT EXISTS panel;"
mariadb -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# Download Jexactyl from Git repository
mkdir -p /var/www
cd /var/www
git clone https://github.com/Jexactyl/Jexactyl.git
cd jexactyl

# Install PHP dependencies with Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
composer install --no-interaction --optimize-autoloader

# Copy .env.example to .env and configure environment variables
cp .env.example .env
sed -i "s/APP_URL=http:\/\/localhost/APP_URL=http:\/\/$(hostname -f)/g" .env
sed -i "s/APP_NAME=Pterodactyl/APP_NAME=Jexactyl/g" .env
sed -i "s/DB_DATABASE=pterodactyl/DB_DATABASE=panel/g" .env
sed -i "s/DB_USERNAME=pterodactyl/DB_USERNAME=pterodactyl/g" .env
sed -i "s/DB_PASSWORD=/DB_PASSWORD=${MYSQL_PASSWORD}/g" .env

# Generate application key
php artisan key:generate

# Run database migrations and seeders
php artisan p:environment:setup
php artisan p:environment:database
php artisan migrate --seed --force
php artisan db:seed --force

# Set correct file permissions
chown -R www-data:www-data /var/www/jexactyl
chmod -R 755 /var/www/jexactyl/storage
chmod -R 755 /var/www/jexactyl/bootstrap/cache

# Create a systemd service for the Jexactyl queue worker
cat <<EOF >/etc/systemd/system/pteroq.service
[Unit]
Description=Jexactyl Queue Worker
After=redis.service mariadb.service
Requires=redis.service mariadb.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/jexactyl
ExecStart=/usr/bin/php artisan queue:work --queue=high,default
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pteroq
systemctl start pteroq
