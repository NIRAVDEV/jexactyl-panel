#!/bin/bash

# Jexactyl Panel Installation Script
# This script automates the installation of Jexactyl Panel on Ubuntu/Debian and CentOS/RHEL.

# --- Global Variables ---
JEXACTYL_DIR="/var/www/jexactyl"
PHP_VERSION="8.4" # Jexactyl typically requires PHP 8.1 or newer. Adjust if needed.

# --- Helper Functions ---

log_info() {
    echo -e "\e[32mINFO:\e[0m $1"
}

log_warning() {
    echo -e "\e[33mWARNING:\e[0m $1"
}

log_error() {
    echo -e "\e[31mERROR:\e[0m $1" >&2
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Please use 'sudo su' or 'sudo ./install.sh'."
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            log_info "Detected OS: $OS $VERSION_ID"
            PKG_MANAGER="apt"
        elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
            log_info "Detected OS: $OS $VERSION_ID"
            PKG_MANAGER="yum"
            if [ "$OS" == "fedora" ]; then
                PKG_MANAGER="dnf" # Fedora uses dnf
            fi
        else
            log_error "Unsupported operating system: $OS. This script supports Ubuntu, Debian, CentOS, and RHEL."
        fi
    else
        log_error "Could not detect operating system. /etc/os-release not found."
    fi
}

get_user_input() {
    read -p "$1" INPUT
    echo "$INPUT"
}

# --- Installation Functions ---

install_dependencies_ubuntu() {
    log_info "Updating system and installing basic dependencies for Ubuntu/Debian..."
    apt update -y && apt upgrade -y
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg2 unzip git wget redis-server

    log_info "Adding Ondrej PHP repository for Debian $VERSION_ID..."
    # Correct method for Debian:
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

    apt update -y

    log_info "Installing PHP $PHP_VERSION and required extensions..."
    apt install -y php$PHP_VERSION-cli php$PHP_VERSION-fpm php$PHP_VERSION-mysql php$PHP_VERSION-pdo php$PHP_VERSION-bcmath php$PHP_VERSION-xml php$PHP_VERSION-mbstring php$PHP_VERSION-tokenizer php$PHP_VERSION-json php$PHP_VERSION-gd php$PHP_VERSION-curl php$PHP_VERSION-zip

    log_info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    log_info "Dependencies installed."
}

install_dependencies_debian() {
    log_ino "Updating system and installing basic dependencies for Debian..."
    apt update -y && apt upgrade -y
    sudo apt install software-properties-common ca-certificates lsb-release apt-transport-https gnupg2 unzip git wget redis-server

    log_ino "Adding PHP repository for Debain $VERSION_ID..."
    sudo sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
    sudo apt update
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

    apt update -y && apt upgrade -y
    log_info "Installing PHP $PHP_VERSION and required extensions..."
    apt install -y php$PHP_VERSION php$PHP_VERSION-fpm php$PHP_VERSION-mysql php$PHP_VERSION-pdo php$PHP_VERSION-bcmath php$PHP_VERSION-xml php$PHP_VERSION-mbstring php$PHP_VERSION-tokenizer php$PHP_VERSION-json php$PHP_VERSION-gd php$PHP_VERSION-curl php$PHP_VERSION-zip

    log_info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    log_info "Dependencies installed."
}

install_dependencies_centos_rhel() {
    log_info "Updating system and installing basic dependencies for CentOS/RHEL..."
    $PKG_MANAGER update -y
    $PKG_MANAGER install -y epel-release
    $PKG_MANAGER install -y curl wget git unzip redis

    log_info "Installing Remi repository for PHP..."
    if [ "$PKG_MANAGER" == "yum" ]; then
        $PKG_MANAGER install -y https://rpms.remiro-repo.net/enterprise/remi-release-$(rpm -E %rhel).rpm
    elif [ "$PKG_MANAGER" == "dnf" ]; then
        dnf install -y https://rpms.remiro-repo.net/fedora/remi-release-$(rpm -E %fedora).rpm
    fi
    $PKG_MANAGER module enable -y php:remi-$PHP_VERSION

    log_info "Installing PHP $PHP_VERSION and required extensions..."
    $PKG_MANAGER install -y php-cli php-fpm php-mysqlnd php-bcmath php-xml php-mbstring php-json php-gd php-curl php-zip php-pdo php-tokenizer

    log_info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Start Redis for CentOS/RHEL
    service redis start
    log_info "Dependencies installed."
}

install_mariadb() {
    log_info "Installing MariaDB..."
    if [ "$PKG_MANAGER" == "apt" ]; then
        apt install -y mariadb-server mariadb-client
    elif [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        $PKG_MANAGER install -y mariadb-server mariadb
    fi

    service mariadb start
    log_info "MariaDB installed and started."

    log_info "Securing MariaDB installation. You will be prompted to set a root password, remove anonymous users, disallow root login remotely, and remove the test database."
    mariadb-secure-installation

    log_info "Creating Jexactyl database and user..."
    DB_ROOT_PASSWORD=$(get_user_input "Enter MariaDB root password (set during secure installation): ")
    DB_NAME=$(get_user_input "Enter a name for the Jexactyl database (e.g., jexactyl_panel): ")
    DB_USER=$(get_user_input "Enter a username for the Jexactyl database (e.g., jexactyluser): ")
    DB_PASSWORD=$(get_user_input "Enter a strong password for the Jexactyl database user: ")

        # Add IF NOT EXISTS to prevent error if user/db already exist
    SQL_COMMANDS="CREATE DATABASE IF NOT EXISTS $DB_NAME;
    CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;
    FLUSH PRIVILEGES;"
    # Note: If the user *exists* but with a different password, this will still fail.
    # A more robust solution might involve checking if the user exists first and then ALTER USER or dropping it.
    # For now, IF NOT EXISTS is a good first step.


    echo "$SQL_COMMANDS" | mariadb -u root -p"$DB_ROOT_PASSWORD"

    if [ $? -eq 0 ]; then
        log_info "Jexactyl database and user created successfully."
    else
        log_error "Failed to create Jexactyl database and user. Please check your MariaDB root password and try again."
    fi
}

install_jexactyl() {
    log_info "Downloading and installing Jexactyl Panel..."
    mkdir -p $JEXACTYL_DIR
    cd $JEXACTYL_DIR

    curl -Lo panel.tar.gz https://github.com/jexactyl/jexactyl/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    log_info "Configuring Jexactyl .env file..."
    cp .env.example .env

    log_info "Installing Composer dependencies for Jexactyl. This may take some time..."
    composer install --no-dev --optimize-autoloader

    php artisan key:generate --force

    # Update .env with database details
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env

    log_info "Running Jexactyl database migrations and seeding..."
    php artisan migrate --force --seed

    log_info "Creating Jexactyl administrator user..."
    php artisan p:user:make

    log_info "Setting correct permissions for Jexactyl files..."
    chown -R www-data:www-data $JEXACTYL_DIR # For Ubuntu/Debian
    if [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        chown -R apache:apache $JEXACTYL_DIR # For CentOS/RHEL/Fedora
    fi
}

configure_nginx() {
    log_info "Configuring Nginx for Jexactyl Panel..."
    # Determine the correct user for Nginx/PHP-FPM based on OS
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
        WEBSERVER_USER="www-data"
        PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
    elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        FPM_SOCK="/run/php-fpm/www.sock" # Default for Remi/CentOS
        WEBSERVER_USER="nginx"
        PHP_FPM_SERVICE="php-fpm"
    fi

    # Ensure PHP-FPM uses the correct user
    log_info "Adjusting PHP-FPM user to $WEBSERVER_USER..."
    sed -i "s/^user = apache/user = $WEBSERVER_USER/" /etc/php-fpm.d/www.conf 2>/dev/null || true
    sed -i "s/^group = apache/group = $WEBSERVER_USER/" /etc/php-fpm.d/www.conf 2>/dev/null || true
    sed -i "s/^listen.owner = nobody/listen.owner = $WEBSERVER_USER/" /etc/php-fpm.d/www.conf 2>/dev/null || true
    sed -i "s/^listen.group = nobody/listen.group = $WEBSERVER_USER/" /etc/php-fpm.d/www.conf 2>/dev/null || true

    # Specific for Ubuntu/Debian if using different FPM pool config
    if [ -f "/etc/php/$PHP_VERSION/fpm/pool.d/www.conf" ]; then
        sed -i "s/^user = www-data/user = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
        sed -i "s/^group = www-data/group = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
        sed -i "s/^listen.owner = www-data/listen.owner = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
        sed -i "s/^listen.group = www-data/listen.group = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
    fi

    service $PHP_FPM_SERVICE restart

    NGINX_CONFIG="
server {
    listen 8080;
    server_name $DOMAIN;
    root $JEXACTYL_DIR/public;
    index index.php index.html index.htm;

    charset utf-8;
    gzip on;
    gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xml;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)$;
        fastcgi_pass unix:$FPM_SOCK;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\\.env {
        deny all;
    }

    location ~ /storage {
        deny all;
    }
}
"
    echo "$NGINX_CONFIG" > "/etc/nginx/sites-available/$DOMAIN.conf"
    ln -s "/etc/nginx/sites-available/$DOMAIN.conf" "/etc/nginx/sites-enabled/$DOMAIN.conf"

    # Remove default Nginx config if present
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        unlink "/etc/nginx/sites-enabled/default"
    fi

    service nginx start
    nginx -t && service nginx reload

    log_info "Nginx configured. You can access your panel at http://$DOMAIN"
}

configure_apache() {
    log_info "Configuring Apache for Jexactyl Panel..."
    if [ "$PKG_MANAGER" == "apt" ]; then
        apt install -y apache2 libapache2-mod-fcgid # Install fcgid to connect to PHP-FPM
        a2enmod rewrite # Ensure rewrite module is enabled
        a2enmod proxy_fcgi # Enable proxy_fcgi for connecting to PHP-FPM socket
        a2enmod setenvif # Sometimes needed for PHP-FPM setups

        WEBSERVER_USER="www-data"
        PHP_FPM_SOCKET="/run/php/php${PHP_VERSION}-fpm.sock" # Standard PHP-FPM socket for Ondrej's PPA
        PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

        # Ensure PHP-FPM uses the correct user (should be www-data by default for Ondrej's PPA)
        log_info "Adjusting PHP-FPM user to $WEBSERVER_USER if necessary..."
        if [ -f "/etc/php/$PHP_VERSION/fpm/pool.d/www.conf" ]; then
            sed -i "s/^user = www-data/user = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf 2>/dev/null || true
            sed -i "s/^group = www-data/group = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf 2>/dev/null || true
            sed -i "s/^listen.owner = www-data/listen.owner = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf 2>/dev/null || true
            sed -i "s/^listen.group = www-data/listen.group = $WEBSERVER_USER/" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf 2>/dev/null || true
        fi
        service $PHP_FPM_SERVICE restart # Restart PHP-FPM to apply user/group changes
    fi

    # Apache configuration using PHP-FPM via ProxyPassMatch
    APACHE_CONFIG="
<VirtualHost *:8080>
    ServerAdmin webmaster@localhost
    ServerName $DOMAIN
    DocumentRoot \"$JEXACTYL_DIR/public\"

    # Required for Jexactyl's API routes with encoded slashes
    AllowEncodedSlashes On

    <Directory \"$JEXACTYL_DIR/public\">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        # For Apache 2.4.10 and above with PHP-FPM via Unix socket
        # PHP settings (like upload_max_filesize) must be in php-fpm's config (e.g., /etc/php/$PHP_VERSION/fpm/pool.d/www.conf)
        SetHandler \"proxy:unix:$PHP_FPM_SOCKET|fcgi://localhost/\"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
"
    if [ "$PKG_MANAGER" == "apt" ]; then
        echo "$APACHE_CONFIG" | sudo tee "/etc/apache2/sites-available/$DOMAIN.conf" > /dev/null
        log_info "Enabling the Apache site: $DOMAIN.conf"
        a2ensite "$DOMAIN.conf"
        log_info "Disabling Apache's default site (000-default.conf)..."
        a2dissite 000-default.conf # Disable default site

        # Use service command since systemctl is not available
        log_info "Restarting Apache service..."
        service apache2 restart

        if [ $? -ne 0 ]; then
            log_error "Failed to restart Apache. Check 'sudo apache2ctl configtest' for syntax errors."
        fi
    fi

    log_info "Apache configured. You can access your panel at http://$DOMAIN"
    log_warning "IMPORTANT: PHP settings like 'upload_max_filesize' and 'post_max_size' cannot be in the Apache config when using PHP-FPM."
    log_warning "You must manually add them to your PHP-FPM pool configuration file:"
    log_warning "  For Debian: /etc/php/$PHP_VERSION/fpm/pool.d/www.conf"
    log_warning "  Add these lines under the [www] section:"
    log_warning "  php_admin_value[upload_max_filesize] = 100M"
    log_warning "  php_admin_value[post_max_size] = 100M"
    log_warning "  After editing, restart PHP-FPM: service $PHP_FPM_SERVICE restart"
}



setup_queue_worker() {
    log_warning "Systemd not detected as init system. Cannot set up queue worker as a systemd service."
    log_warning "You will need to manually configure the Jexactyl queue worker for persistent operation."
    log_warning "RECOMMENDED: Use Supervisor for robust process management."
    log_warning "Installation for Supervisor:"
    log_warning "  sudo apt install -y supervisor"
    log_warning "Then, create a config file like /etc/supervisor/conf.d/jexactyl.conf with content similar to:"
    log_warning "  [program:jexactyl-queue]"
    log_warning "  command=/usr/bin/php $JEXACTYL_DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3"
    log_warning "  process_name=%(program_name)s_%(process_num)02d"
    log_warning "  autostart=true"
    log_warning "  autorestart=true"
    log_warning "  user=www-data"
    log_warning "  numprocs=1"
    log_warning "  redirect_stderr=true"
    log_warning "  stdout_logfile=/var/www/jexactyl/storage/logs/queue_worker.log"
    log_warning "  stopwaitsecs=3600"
    log_warning "After creating the file, run:"
    log_warning "  sudo systemctl enable supervisor # Or service supervisor enable/start if systemctl works for supervisor"
    log_warning "  sudo service supervisor restart"
    log_warning "  sudo supervisorctl reread"
    log_warning "  sudo supervisorctl update"
    log_warning "  sudo supervisorctl start jexactyl-queue"
    log_warning "Alternative (less robust): Set up a cron job for the Laravel scheduler and run 'php artisan queue:work' using 'screen' or 'nohup'."
    log_warning "  Cron: * * * * * cd $JEXACTYL_DIR && /usr/bin/php artisan schedule:run >> /dev/null 2>&1"
}



setup_ssl() {
    log_info "Setting up SSL with Certbot (Let's Encrypt)..."
    if [ "$WEBSERVER_CHOICE" == "nginx" ]; then
        if [ "$PKG_MANAGER" == "apt" ]; then
            apt install -y certbot python3-certbot-nginx
        fi
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$ADMIN_EMAIL" --redirect --no-eff-email
        # Use service command for non-systemd environment
        service nginx restart
    elif [ "$WEBSERVER_CHOICE" == "apache" ]; then
        if [ "$PKG_MANAGER" == "apt" ]; then
            apt install -y certbot python3-certbot-apache
        fi
        certbot --apache -d "$DOMAIN" --non-interactive --agree-tos --email "$ADMIN_EMAIL" --redirect --no-eff-email
        # Use service command for non-systemd environment
        service apache2 restart
    fi

    if [ $? -eq 0 ]; then
        log_info "SSL certificate obtained and configured successfully for $DOMAIN."
        log_info "Your Jexactyl Panel is now accessible at https://$DOMAIN"
    else
        log_error "Failed to obtain SSL certificate. Please check Certbot logs for details."
    fi
}

# --- Main Script Logic ---

check_root
detect_os

log_info "Starting Jexactyl Panel installation script..."

# --- User Choices ---
WEBSERVER_CHOICE=""
while true; do
    read -p "Which web server do you want to use? (nginx/apache): " WS_INPUT
    WS_INPUT_LOWER=$(echo "$WS_INPUT" | tr '[:upper:]' '[:lower:]')
    if [[ "$WS_INPUT_LOWER" == "nginx" || "$WS_INPUT_LOWER" == "apache" ]]; then
        WEBSERVER_CHOICE="$WS_INPUT_LOWER"
        break
    else
        log_warning "Invalid choice. Please enter 'nginx' or 'apache'."
    fi
done

DOMAIN=$(get_user_input "Enter the domain name for your Jexactyl Panel (e.g., panel.example.com): ")

USE_SSL=""
while true; do
    read -p "Do you want to enable SSL with Certbot (Let's Encrypt)? (yes/no): " SSL_INPUT
    SSL_INPUT_LOWER=$(echo "$SSL_INPUT" | tr '[:upper:]' '[:lower:]')
    if [[ "$SSL_INPUT_LOWER" == "yes" || "$SSL_INPUT_LOWER" == "no" ]]; then
        USE_SSL="$SSL_INPUT_LOWER"
        break
    else
        log_warning "Invalid choice. Please enter 'yes' or 'no'."
    fi
done

if [ "$USE_SSL" == "yes" ]; then
    ADMIN_EMAIL=$(get_user_input "Enter your email address for Certbot (for urgent renewal notices): ")
fi

# --- Execution Steps ---

log_info "Installing dependencies..."
# [ "$OS" == "debian" ]; then
     install_dependencies_debian
#elif [ "$OS" == "ubuntu" ]; then
 #   install_dependencies_ubuntu
#elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
 #   install_dependencies_centos_rhel
#fi

install_mariadb

install_jexactyl

if [ "$WEBSERVER_CHOICE" == "nginx" ]; then
    configure_nginx
elif [ "$WEBSERVER_CHOICE" == "apache" ]; then
    configure_apache
fi

setup_queue_worker

if [ "$USE_SSL" == "yes" ]; then
    setup_ssl
else
    log_info "SSL not enabled. Your panel will be accessible via HTTP."
    log_info "Please ensure your firewall allows traffic on port 80 (and 443 if you plan to add SSL later)."
fi

log_info "Jexactyl Panel installation complete!"
log_info "You should now be able to access your panel at: http://$DOMAIN (or https://$DOMAIN if SSL was enabled)."
log_info "Remember to log in to your panel using the admin user created during the 'php artisan p:user:make' step."
log_info "If you face any issues, check the logs in $JEXACTYL_DIR/storage/logs/ and your web server error logs."
