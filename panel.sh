#!/bin/bash

# Jexactyl Installer Script
LOG_FILE="/var/log/jexactyl_install.log"
touch "$LOG_FILE"

# Function to log commands and their output
log_command() {
    echo "Running: $*" | tee -a "$LOG_FILE"
    if "$@"; then
        echo "SUCCESS: $*" | tee -a "$LOG_FILE"
    else
        echo "ERROR: $* failed. Check $LOG_FILE for details." | tee -a "$LOG_FILE"
        exit 1
    fi
}

echo "Starting Jexactyl installation..." | tee -a "$LOG_FILE"

# Ask for variables
read -p "Enter your database password for 'jexactyl' user: " DB_PASSWORD
read -p "Enter your Panel URL (e.g., https://panel.example.com): " PANEL_URL
read -p "Enter your Panel API Key: " PANEL_API_KEY
read -p "Enter your Jexactyl instance URL (e.g., https://dash.example.com): " INSTANCE_URL
read -p "Enter your Jexactyl license key: " LICENSE_KEY
read -p "Enter your domain for Certbot (e.g., example.com): " DOMAIN
read -p "Enter your admin account email: " ADMIN_EMAIL
read -p "Enter PHP version (e.g., 8.3): " PHP_VERSION

# Web Server Option (Apache or Nginx)
read -p "Choose your web server (apache/nginx): " WEBSERVER

echo "Updating and upgrading system packages..." | tee -a "$LOG_FILE"
log_command apt update && apt upgrade -y

# Install necessary dependencies
echo "Installing dependencies..." | tee -a "$LOG_FILE"
log_command apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

if [[ "$WEBSERVER" == "apache" ]]; then
    log_command apt install apache2 libapache2-mod-php php${PHP_VERSION}-fpm -y
    # Apache config
    cat <<EOF > /etc/apache2/sites-available/jexactyl.conf
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot "/var/www/jexactyl/public"
    AllowEncodedSlashes On
    php_value upload_max_filesize 100M
    php_value post_max_size 100M
    <Directory "/var/www/jexactyl/public">
        AllowOverride all
        Require all granted
    </Directory>
</VirtualHost>
EOF
    log_command a2ensite jexactyl.conf
    log_command service apache2 restart
elif [[ "$WEBSERVER" == "nginx" ]]; then
    log_command apt install nginx php${PHP_VERSION}-fpm -y
    # Nginx config
    cat <<EOF > /etc/nginx/sites-available/jexactyl
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/jexactyl/public;
    index index.html index.htm index.php;
    charset utf-8;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
    }
}
EOF
    log_command ln -s /etc/nginx/sites-available/jexactyl /etc/nginx/sites-enabled/
    log_command systemctl restart nginx
else
    echo "Invalid web server choice."
    exit 1
fi

# SSL Setup with Certbot (optional)
read -p "Do you want to enable SSL with Certbot? (yes/no): " ENABLE_SSL
if [[ "$ENABLE_SSL" == "yes" ]]; then
    log_command apt install certbot python3-certbot-nginx -y
    certbot certonly --nginx -d "$DOMAIN"
    echo "SSL certificates installed successfully." | tee -a "$LOG_FILE"
else
    echo "Skipping SSL setup."
fi

# Redis Setup (Optional)
read -p "Do you want to enable Redis? (yes/no): " ENABLE_REDIS
if [[ "$ENABLE_REDIS" == "yes" ]]; then
    log_command apt install redis-server -y
    # Enable Redis if systemd is available
    if command -v systemctl &> /dev/null; then
        log_command systemctl enable --now redis-server
    else
        log_command service redis-server start
    fi
    echo "Redis setup complete." | tee -a "$LOG_FILE"
fi

# Install Composer
echo "Installing Composer..." | tee -a "$LOG_FILE"
log_command curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer


# Setup Jexactyl
echo "Setting up Jexactyl directory..." | tee -a "$LOG_FILE"
log_command mkdir -p /var/www/jexactyl
log_command cd /var/www/jexactyl
log_command curl -Lo Jexactyl.zip https://github.com/Jexactyl/Jexactyl/releases/latest/download/Jexactyl.zip
log_command unzip -o Jexactyl.zip

# Set permissions
echo "Setting permissions..." | tee -a "$LOG_FILE"
log_command chown -R www-data:www-data /var/www/jexactyl/*

# Run make commands
echo "Running make commands..." | tee -a "$LOG_FILE"
log_command cd /var/www/jexactyl
log_command make set-prod
log_command make get-frontend

# Create MariaDB user and database
echo "Creating MariaDB user and database..." | tee -a "$LOG_FILE"
log_command mariadb -u root -p <<EOF
CREATE USER 'jexactyl'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
CREATE DATABASE jexactyl;
GRANT ALL PRIVILEGES ON jexactyl.* TO 'jexactyl'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
exit
EOF

# Run migrations and setup
echo "Running migrations and setup..." | tee -a "$LOG_FILE"
log_command php artisan migrate
log_command php artisan key:generate

# Create Admin user
echo "Creating admin user..." | tee -a "$LOG_FILE"
log_command php artisan make:admin "$ADMIN_EMAIL"

# Final setup and permissions
echo "Finalizing setup..." | tee -a "$LOG_FILE"
log_command chown -R www-data:www-data /var/www/jexactyl/*

echo "Jexactyl installation complete!" | tee -a "$LOG_FILE"
echo "Please navigate to your instance URL: $INSTANCE_URL" | tee -a "$LOG_FILE"
