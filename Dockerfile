FROM python:3.8-slim

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV ODOO_VERSION 15.0
ENV ODOO_USER odoo
ENV ODOO_HOME /opt/odoo

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl node-less npm netcat \
    libpq-dev python3-dev libxml2-dev libxslt1-dev \
    libldap2-dev libsasl2-dev libffi-dev libjpeg-dev \
    libpng-dev zlib1g-dev libjpeg8-dev liblcms2-dev \
    libblas-dev libatlas-base-dev libssl-dev \
    libtiff-dev libwebp-dev gcc make build-essential \
    xz-utils ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.5-1/wkhtmltox_0.12.5-1.buster_amd64.deb && \
    apt install -y ./wkhtmltox_0.12.5-1.buster_amd64.deb && \
    rm wkhtmltox_0.12.5-1.buster_amd64.deb

RUN useradd -m -d ${ODOO_HOME} -U -r -s /bin/bash ${ODOO_USER}

USER ${ODOO_USER}
WORKDIR ${ODOO_HOME}
RUN git clone --depth 1 --branch ${ODOO_VERSION} https://www.github.com/odoo/odoo ${ODOO_HOME}

USER root
RUN pip install --upgrade pip && pip install setuptools wheel \
 && pip install -r ${ODOO_HOME}/requirements.txt

COPY --chown=odoo:odoo odoo.conf ${ODOO_HOME}/odoo.conf

EXPOSE 8069

USER odoo
CMD ["python3", "odoo-bin", "-c", "/opt/odoo/odoo.conf"]

