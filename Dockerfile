ARG IMAGE_BASE=docker.io/library/debian
ARG IMAGE_TAG=trixie-slim

FROM docker.io/library/${IMAGE_BASE}:${IMAGE_TAG}

# Create PostgreSQL user and directories
RUN useradd -r -d /var/lib/postgresql -s /bin/bash postgres \
    && mkdir -pv /var/lib/postgresql/data \
    && mkdir -pv /opt/patroni \
    && chown -vR postgres:postgres /var/lib/postgresql/data /opt/patroni
    
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get full-upgrade -y \
    && apt-get install -y \
    postgresql \
    postgresql-contrib \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python-is-python3 \
    build-essential \
    libpq-dev \
    curl \
    wget \
    vim \
    net-tools \
    iproute2 \
    procps \
    iputils-ping \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY ./patroni.yaml /etc/patroni/patroni.yaml
COPY ./postgresql.conf /etc/postgresql/postgresql.conf
COPY ./pg_hba.conf /etc/postgresql/pg_hba.conf
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

# Set permissions
RUN chmod +x /usr/local/bin/entrypoint.sh && sed -i 's/\r//g' /usr/local/bin/entrypoint.sh

RUN ln -sfv /bin/bash /bin/sh \
    && echo 'dash dash/sh boolean false' | debconf-set-selections \
    && dpkg-reconfigure dash \
    && echo 'PATH="/var/lib/postgresql/bin:/var/lib/postgresql/.local/bin:$PATH";. /opt/patroni/bin/activate' >> /var/lib/postgresql/.bashrc \
    && chown -v postgres:postgres /var/lib/postgresql/.bashrc

USER postgres

# Install Patroni and related Python packages
RUN python3 -m venv /opt/patroni \
    && /opt/patroni/bin/python -m pip install --no-cache-dir --upgrade pip setuptools

RUN /opt/patroni/bin/python -m pip install --no-cache-dir --upgrade --no-build-isolation --use-pep517 \
    patroni[etcd] \
    psycopg2-binary \
    pyyaml \
    requests \
    python-etcd

# Set environment variables
ENV PGDATA=/var/lib/postgresql/data \
    POSTGRES_PASSWORD=postgres \
    PATRONI_NAME=patroni \
    ETCD_HOST=etcd \
    ETCD_PORT=2379

WORKDIR /opt/patroni

# Expose PostgreSQL port and Patroni API port
EXPOSE 5432 8008

CMD ["/opt/patroni/bin/patroni", "/etc/patroni/patroni.yaml"]

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD pg_isready -U postgres -d postgres || exit 1
