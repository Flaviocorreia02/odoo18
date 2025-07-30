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
    gosu \
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

# Create entrypoint script
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
# Function to wait for PostgreSQL\n\
wait_for_postgres() {\n\
    echo "Waiting for PostgreSQL..."\n\
    while ! python3 -c "\n\
import psycopg2\n\
import os\n\
try:\n\
    conn = psycopg2.connect(\n\
        host=os.environ.get('\''DB_HOST'\'', '\''localhost'\''),\n\
        port=os.environ.get('\''DB_PORT'\'', '\''5432'\''),\n\
        user=os.environ.get('\''DB_USER'\'', '\''odoo'\''),\n\
        password=os.environ.get('\''DB_PASSWORD'\'', '\'\''),\n\
        dbname='\''postgres'\''\n\
    )\n\
    conn.close()\n\
    print('\''PostgreSQL is ready!'\'')\n\
    exit(0)\n\
except Exception as e:\n\
    print(f'\''PostgreSQL not ready: {e}'\'')\n\
    exit(1)\n\
"; do\n\
        sleep 5\n\
    done\n\
}\n\
\n\
# Wait for database if DB_HOST is set\n\
if [ -n "$DB_HOST" ]; then\n\
    wait_for_postgres\n\
fi\n\
\n\
# Generate configuration file from environment variables\n\
cat > /etc/odoo/odoo.conf << EOL\n\
[options]\n\
addons_path = /opt/odoo/odoo/addons\n\
data_dir = /var/lib/odoo\n\
logfile = /var/log/odoo/odoo.log\n\
log_level = ${LOG_LEVEL:-info}\n\
\n\
# Database settings\n\
db_host = ${DB_HOST:-localhost}\n\
db_port = ${DB_PORT:-5432}\n\
db_user = ${DB_USER:-odoo}\n\
db_password = ${DB_PASSWORD:-}\n\
db_sslmode = ${DB_SSLMODE:-prefer}\n\
\n\
# Server settings\n\
http_port = ${PORT:-8069}\n\
http_interface = 0.0.0.0\n\
proxy_mode = True\n\
\n\
# Security\n\
admin_passwd = ${ADMIN_PASSWORD:-admin}\n\
list_db = ${LIST_DB:-False}\n\
\n\
# Performance\n\
max_cron_threads = ${MAX_CRON_THREADS:-2}\n\
workers = ${WORKERS:-0}\n\
limit_memory_hard = ${LIMIT_MEMORY_HARD:-2684354560}\n\
limit_memory_soft = ${LIMIT_MEMORY_SOFT:-2147483648}\n\
limit_request = ${LIMIT_REQUEST:-8192}\n\
limit_time_cpu = ${LIMIT_TIME_CPU:-60}\n\
limit_time_real = ${LIMIT_TIME_REAL:-120}\n\
limit_time_real_cron = ${LIMIT_TIME_REAL_CRON:-300}\n\
\n\
# Additional options\n\
without_demo = ${WITHOUT_DEMO:-True}\n\
csv_internal_sep = ,\n\
EOL\n\
\n\
# Ensure proper ownership\n\
chown -R odoo:odoo /var/lib/odoo /var/log/odoo /etc/odoo\n\
\n\
# Execute command as odoo user\n\
exec gosu odoo "$@"\n' > /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Create basic odoo.conf template
RUN printf '[options]\n\
addons_path = /opt/odoo/odoo/addons\n\
data_dir = /var/lib/odoo\n\
logfile = /var/log/odoo/odoo.log\n\
http_port = 8069\n\
http_interface = 0.0.0.0\n\
proxy_mode = True\n' > $ODOO_CONFIG_DIR/odoo.conf

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
