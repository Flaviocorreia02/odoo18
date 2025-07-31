FROM python:3.9-slim-bullseye

# Set environment variables
ENV ODOO_VERSION=15.0
ENV ODOO_USER=odoo
ENV ODOO_HOME=/opt/odoo
ENV ODOO_CONFIG_DIR=/etc/odoo
ENV ODOO_LOG_DIR=/var/log/odoo
ENV ODOO_DATA_DIR=/var/lib/odoo
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies - minimal set
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libsasl2-dev \
    libpq-dev \
    libjpeg-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    libssl-dev \
    node-less \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install gosu
RUN curl -o /usr/local/bin/gosu -SL "https://github.com/tianon/gosu/releases/download/1.14/gosu-$(dpkg --print-architecture)" \
    && chmod +x /usr/local/bin/gosu

# Install rtlcss
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
RUN pip3 install --user --no-cache-dir wheel setuptools
RUN pip3 install --user --no-cache-dir -r odoo/requirements.txt

# Install additional packages
RUN pip3 install --user --no-cache-dir \
    psycopg2-binary \
    phonenumbers \
    num2words \
    python-ldap

# Switch back to root
USER root

# Create entrypoint script
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
# Wait for PostgreSQL\n\
if [ -n "$DB_HOST" ]; then\n\
    echo "Waiting for PostgreSQL..."\n\
    while ! python3 -c "import psycopg2; psycopg2.connect(host='\''$DB_HOST'\'', port='\''${DB_PORT:-5432}'\'', user='\''${DB_USER:-odoo}'\'', password='\''$DB_PASSWORD'\'', dbname='\''odoodatabase'\'')" 2>/dev/null; do\n\
        sleep 2\n\
    done\n\
    echo "PostgreSQL is ready!"\n\
fi\n\
\n\
# Generate config\n\
cat > /etc/odoo/odoo.conf << EOL\n\
[options]\n\
addons_path = /opt/odoo/odoo/addons\n\
data_dir = /var/lib/odoo\n\
logfile = /var/log/odoo/odoo.log\n\
log_level = ${LOG_LEVEL:-info}\n\
db_host = ${DB_HOST:-localhost}\n\
db_port = ${DB_PORT:-5432}\n\
db_user = ${DB_USER:-odoo}\n\
db_password = ${DB_PASSWORD:-}\n\
http_port = ${PORT:-8069}\n\
http_interface = 0.0.0.0\n\
proxy_mode = True\n\
admin_passwd = ${ADMIN_PASSWORD:-admin}\n\
list_db = ${LIST_DB:-False}\n\
workers = ${WORKERS:-0}\n\
max_cron_threads = ${MAX_CRON_THREADS:-2}\n\
without_demo = ${WITHOUT_DEMO:-True}\n\
EOL\n\
\n\
chown -R odoo:odoo /var/lib/odoo /var/log/odoo /etc/odoo\n\
exec gosu odoo "$@"\n' > /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Basic config
RUN printf '[options]\n\
addons_path = /opt/odoo/odoo/addons\n\
data_dir = /var/lib/odoo\n\
logfile = /var/log/odoo/odoo.log\n\
http_port = ${PORT:-8069}\n\
http_interface = 0.0.0.0\n\
proxy_mode = True\n' > $ODOO_CONFIG_DIR/odoo.conf \
    && chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG_DIR/odoo.conf

EXPOSE ${PORT:-8069}

WORKDIR $ODOO_HOME

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8069}/web/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "odoo/odoo-bin", "-c", "/etc/odoo/odoo.conf"]
