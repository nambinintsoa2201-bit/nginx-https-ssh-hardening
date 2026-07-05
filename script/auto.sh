#!/bin/bash

# Variables directories
BUILD_DIR="./dist"
WEB_ROOT="/var/www/html"
SSL_DIR="/etc/nginx/ssl"
NGINX_CONF="/etc/nginx/sites-available/default"


# Fonctiom
log() {
    echo -e "\n\033[1;033m>>> $1\033[0m"
}

log_error() {
    echo -e "\n\033[1;031m!!!>>> ERROR : $1\033[0m"
}

#fonction de verification 
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found. Please install it and try again."
        return 1
    fi
}

#log "verification des prerequis"
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

# -d test if directory exists
if [ ! -d "$BUILD_DIR" ]; then
    log_error "Build directory '$BUILD_DIR' does not exist. Please run the build script first."
    exit 1
fi  

log "nginx installation"

if check_commande nginx; then
    echo "nginx is already installed."
else
    apt update
    apt install -y nginx
fi

# Deploy the build files to the web directory
log "Deploying build files to $WEB_ROOT"

rm -rf "${WEB_ROOT}"/*

cp -r "$BUILD_DIR"/* "$WEB_ROOT"/

#Permission for the web directory
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

echo "Build files deployed successfully to $WEB_ROOT"

#Certificat SSL
log "SSL certificate generation"
mkdir -p "$SSL_DIR"

if [ -f "$SSL_DIR/selfsigned.key" ] && [ -f "$SSL_DIR/selfsigned.crt" ]; then
    log "SSL certificate already exists."
else
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/selfsigned.key" \
        -out "$SSL_DIR/selfsigned.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=example.com"
    log "Self-signed SSL certificate generated."
fi

#nginx configuration
log "Configuring Nginx"
cat > "$NGINX_CONF" << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    server_name _;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }
}

EOF

log "Testing Nginx configuration"
nginx -t

log "restarting Nginx"
systemctl restart nginx

#Firewall configuration
log "Configuring UFW firewall"
if check_command ufw; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 2220/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
else
    log_error "UFW is not installed. Please install it and configure the firewall manually."
fi

# RESUmE
log "Deployment completed successfully!"
echo "Your website is now accessible at https://<your-server-ip>"
echo "SSH is accessible on port 2220."