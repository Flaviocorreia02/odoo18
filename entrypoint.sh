#!/bin/bash
set -e

# Wait for PostgreSQL
if [ -n "$DB_HOST" ]; then
    echo "Waiting for PostgreSQL..."
    echo "Attempting to connect to: $DB_HOST:${DB_PORT:-5432}"
    
    # More robust connection check - just check if we can connect to postgres db
    max_attempts=30
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if python3 -c "
import psycopg2
import sys
try:
    conn = psycopg2.connect(
        host='$DB_HOST',
        port='${DB_PORT:-5432}',
        user='${DB_USER:-odoo}',
        password='$DB_PASSWORD',
        dbname='postgres',  # Connect to default postgres db first
        connect_timeout=10
    )
    conn.close()
    print('PostgreSQL connection successful!')
    sys.exit(0)
except Exception as e:
    print(f'Connection attempt {attempt}: {e}')
    sys.exit(1)
" 2>/dev/null; then
            echo "PostgreSQL is ready!"
            break
        else
            echo "PostgreSQL not ready, attempt $attempt/$max_attempts"
            if [ $attempt -eq $max_attempts ]; then
                echo "Failed to connect to PostgreSQL after $max_attempts attempts"
                exit 1
            fi
            sleep 2
            attempt=$((attempt + 1))
        fi
    done
else
    echo "No DB_HOST specified, skipping PostgreSQL check"
fi

# Ensure directories exist and have correct permissions
mkdir -p /var/lib/odoo /var/log/odoo /etc/odoo
chown -R odoo:odoo /var/lib/odoo /var/log/odoo /etc/odoo

# Generate config
cat > /etc/odoo/odoo.conf << EOL
[options]
addons_path = /opt/odoo/odoo/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
log_level = ${LOG_LEVEL:-info}
db_host = ${DB_HOST:-localhost}
db_port = ${DB_PORT:-5432}
db_user = ${DB_USER:-odoo}
db_password = ${DB_PASSWORD:-}
http_port = ${PORT:-8069}
http_interface = 0.0.0.0
proxy_mode = True
admin_passwd = ${ADMIN_PASSWORD:-admin}
list_db = ${LIST_DB:-False}
workers = ${WORKERS:-0}
max_cron_threads = ${MAX_CRON_THREADS:-2}
without_demo = ${WITHOUT_DEMO:-True}
db_maxconn = ${DB_MAXCONN:-64}
db_template = template0
EOL

echo "Generated Odoo configuration:"
cat /etc/odoo/odoo.conf

echo "Starting Odoo with command: $@"
exec gosu odoo "$@"