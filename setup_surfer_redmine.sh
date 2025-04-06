#!/bin/bash

set -e

# Variables
DB_USER="Surfer"
DB_PASS="dude"
DB_NAME="surfer"
INSTALL_DIR="/var/lib/surfer"
RUBY_VERSION="3.3.7"
RUBY_TARBALL="ruby-${RUBY_VERSION}.tar.gz"
RUBY_SRC_DIR="ruby-${RUBY_VERSION}"
PASSENGER_GEM_DIR="/usr/local/lib/ruby/gems/3.3.0/gems/passenger-6.0.26"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "=== Checking for root privileges ==="
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

echo "=== Updating package lists and installing dependencies ==="
apt update
apt install -y build-essential zlib1g-dev libssl-dev libreadline-dev libyaml-dev \
  libcurl4-openssl-dev libffi-dev mysql-server libmysqlclient-dev apache2 apache2-dev \
  subversion git curl imagemagick redis-server

echo "=== Installing Ruby if not already installed ==="
if ! ruby -v | grep -q "${RUBY_VERSION}"; then
  curl -O https://cache.ruby-lang.org/pub/ruby/3.3/${RUBY_TARBALL}
  tar xvf ${RUBY_TARBALL}
  cd ${RUBY_SRC_DIR}
  ./configure --disable-install-doc
  make
  make install
  cd ..
fi

echo "=== Configuring MySQL user and database ==="
mysql -u root <<EOF
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4;
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "=== Downloading Redmine if not already installed ==="
if [ ! -d "${INSTALL_DIR}" ]; then
  mkdir -p ${INSTALL_DIR}
  chown www-data ${INSTALL_DIR}
  sudo -u www-data svn co https://svn.redmine.org/redmine/branches/6.0-stable ${INSTALL_DIR}
fi

echo "=== Creating database.yml ==="
DB_YML="${INSTALL_DIR}/config/database.yml"
if [ ! -f "${DB_YML}" ]; then
  mkdir -p "$(dirname ${DB_YML})"
  cat > ${DB_YML} <<EOL
production:
  adapter: mysql2
  database: ${DB_NAME}
  host: localhost
  username: ${DB_USER}
  password: "${DB_PASS}"
  encoding: utf8mb4
EOL
fi

echo "=== Creating configuration.yml ==="
CONFIG_YML="${INSTALL_DIR}/config/configuration.yml"
if [ ! -f "${CONFIG_YML}" ]; then
  cat > ${CONFIG_YML} <<EOL
production:
  email_delivery:
    delivery_method: :smtp
    smtp_settings:
      address: "localhost"
      port: 25
      domain: "example.com"
EOL
fi

cd ${INSTALL_DIR}
echo "=== Installing bundler and required gems ==="
sudo -u www-data bundle config set --local without 'development test'
sudo -u www-data bundle install || true

echo "=== Running Redmine setup ==="
[ ! -f config/initializers/secret_token.rb ] && sudo -u www-data bin/rake generate_secret_token
sudo -u www-data bin/rake db:migrate RAILS_ENV="production"

echo "=== Installing Passenger ==="
if ! gem list passenger -i > /dev/null; then
  gem install passenger -N
fi
if [ ! -f "${PASSENGER_GEM_DIR}/buildout/apache2/mod_passenger.so" ]; then
  passenger-install-apache2-module --auto --languages ruby
fi

echo "=== Configuring Apache ==="
APACHE_CONF="/etc/apache2/conf-available/surfer.conf"
if [ ! -f "${APACHE_CONF}" ]; then
  cat > ${APACHE_CONF} <<EOL
<Directory "${INSTALL_DIR}/public">
  Require all granted
</Directory>

LoadModule passenger_module ${PASSENGER_GEM_DIR}/buildout/apache2/mod_passenger.so
<IfModule mod_passenger.c>
  PassengerRoot ${PASSENGER_GEM_DIR}
  PassengerDefaultRuby /usr/local/bin/ruby
</IfModule>

<Directory ${INSTALL_DIR}/public>
    Allow from all
    Options -MultiViews
    Require all granted
</Directory>
EOL
  a2enconf surfer
  sed -i "s|DocumentRoot /var/www/html|DocumentRoot ${INSTALL_DIR}/public|g" /etc/apache2/sites-enabled/000-default.conf
  apache2ctl configtest
  systemctl reload apache2
fi

echo "=== Updating ImageMagick PDF policy ==="
POLICY_FILE="/etc/ImageMagick-6/policy.xml"
if grep -q 'pattern="PDF"' "${POLICY_FILE}"; then
  sed -i 's|<policy domain="coder" rights="none" pattern="PDF" />|<policy domain="coder" rights="read|write" pattern="PDF" />|' "${POLICY_FILE}"
fi

echo "=== Setting up Sidekiq ==="
GEMFILE_LOCAL="${INSTALL_DIR}/Gemfile.local"
[ ! -f "${GEMFILE_LOCAL}" ] && echo "gem 'sidekiq'" > "${GEMFILE_LOCAL}" || grep -q sidekiq "${GEMFILE_LOCAL}" || echo "gem 'sidekiq'" >> "${GEMFILE_LOCAL}"
sudo -u www-data bundle install

echo "=== Configuring Sidekiq environment ==="
cat > ${INSTALL_DIR}/config/additional_environment.rb <<EOL
config.active_job.queue_adapter = :sidekiq
EOL

cat > ${INSTALL_DIR}/config/sidekiq.yml <<EOL
:concurrency: 5
:queues:
  - default
  - mailers
EOL

echo "=== Starting Sidekiq ==="
sudo -u www-data bundle exec sidekiq -C config/sidekiq.yml -e production &

echo "=== Setup complete. Please verify Redmine is accessible. ==="
