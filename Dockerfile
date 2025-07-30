FROM ubuntu:20.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV ODOO_VERSION=15.0
ENV ODOO_USER=odoo
ENV ODOO_HOME=/opt/odoo
ENV ODOO_CONFIG_DIR=/etc/odoo
ENV ODOO_LOG_DIR=/var/log/odoo
ENV ODOO_DATA_DIR=/var/lib/odoo

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    dirmngr \
    fonts-noto-cjk \
    gnupg \
    libssl-dev \
    node-less \
    npm \
    python3-dev \
    python3-pip \
    python3-phonenumbers \
    python3-pyldap \
    python3-qrcode \
    python3-renderpm \
    python3-setuptools \
    python3-slugify \
    python3-vobject \
    python3-watchdog \
    python3-xlrd \
    python3-xlwt \
    xz-utils \
    git \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libevent-dev \
    libsasl2-dev \
    libldap2-dev \
    libpq-dev \
    libjpeg-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    wkhtmltopdf \
    && rm -rf /var/lib/apt/lists/*

# Install rtlcss (required for Right-to-Left languages)
RUN npm install -g rtlcss

# Create odoo user
RUN useradd --create-home --home-dir $ODOO_HOME --no-log-init --shell /bin/bash $ODOO_USER

# Create directories
RUN mkdir -p $ODOO_CONFIG_DIR $ODOO_LOG_DIR $ODOO_DATA_DIR \
    && chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME $ODOO_CONFIG_DIR $ODOO_LOG_DIR $ODOO_DATA_DIR

# Switch to odoo user
USER $ODOO_USER

# Download and install Odoo
WORKDIR $ODOO_HOME
RUN git clone --depth 1 --branch $ODOO_VERSION https://github.com/odoo/odoo.git odoo

# Install Python dependencies
RUN pip3 install --user --no-cache-dir \
    wheel \
    -r odoo/requirements.txt

# Install additional Python packages for better functionality
RUN pip3 install --user --no-cache-dir \
    psycopg2-binary \
    phonenumbers \
    Pillow \
    reportlab \
    num2words

# Switch back to root for final configurations
USER root

# Copy configuration file
COPY --chown=$ODOO_USER:$ODOO_USER odoo.conf $ODOO_CONFIG_DIR/

# Create entrypoint script
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# Function to wait for PostgreSQL
wait_for_postgres() {
    echo "Waiting for PostgreSQL..."
    while ! python3 -c "
import psycopg2
import os
try:
    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        user=os.environ.get('DB_USER', 'odoo'),
        password=os.environ.get('DB_PASSWORD', ''),
        dbname='postgres'
    )
    conn.close()
    print('PostgreSQL is ready!')
    exit(0)
except Exception as e:
    print(f'PostgreSQL not ready: {e}')
    exit(1)
"; do
        sleep 5
    done
}

# Wait for database if DB_HOST is set
if [ -n "$DB_HOST" ]; then
    wait_for_postgres
fi

# Generate configuration file from environment variables
cat > /etc/odoo/odoo.conf << EOL
[options]
addons_path = /opt/odoo/odoo/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
log_level = ${LOG_LEVEL:-info}

# Database settings
db_host = ${DB_HOST:-localhost}
db_port = ${DB_PORT:-5432}
db_user = ${DB_USER:-odoo}
db_password = ${DB_PASSWORD:-}
db_sslmode = ${DB_SSLMODE:-prefer}

# Server settings
http_port = ${PORT:-8069}
http_interface = 0.0.0.0
proxy_mode = True

# Security
admin_passwd = ${ADMIN_PASSWORD:-admin}
list_db = ${LIST_DB:-False}

# Performance
max_cron_threads = ${MAX_CRON_THREADS:-2}
workers = ${WORKERS:-0}
limit_memory_hard = ${LIMIT_MEMORY_HARD:-2684354560}
limit_memory_soft = ${LIMIT_MEMORY_SOFT:-2147483648}
limit_request = ${LIMIT_REQUEST:-8192}
limit_time_cpu = ${LIMIT_TIME_CPU:-60}
limit_time_real = ${LIMIT_TIME_REAL:-120}
limit_time_real_cron = ${LIMIT_TIME_REAL_CRON:-300}

# Additional options
without_demo = ${WITHOUT_DEMO:-True}
csv_internal_sep = ,
EOL

# Ensure proper ownership
chown -R odoo:odoo /var/lib/odoo /var/log/odoo /etc/odoo

# Execute command as odoo user
exec gosu odoo "$@"
EOF

# Install gosu for better su functionality
RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/*

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Create basic odoo.conf template (will be overridden by entrypoint)
RUN cat > $ODOO_CONFIG_DIR/odoo.conf << 'EOF'
[options]
addons_path = /opt/odoo/odoo/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
http_port = 8069
http_interface = 0.0.0.0
proxy_mode = True
EOF

# Set proper ownership for config
RUN chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG_DIR/odoo.conf

# Expose port
EXPOSE 8069

# Set working directory
WORKDIR $ODOO_HOME

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8069}/web/health || exit 1

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["python3", "odoo/odoo-bin", "-c", "/etc/odoo/odoo.conf"]

