# Dockerfile
FROM debian:bullseye-slim

LABEL maintainer="jeroen.keizer@outlook.com"

# Install curl, gnupg, and CA certs first
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates

# Add PostgreSQL signing key to a scoped keyring
RUN curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

# Add the PostgreSQL repo using signed-by
RUN echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    bash \
    gzip \
    openssl \
    tzdata \
    passwd \
    cron \
    postgresql-client-17

RUN apt-get purge -y curl gnupg ca-certificates
RUN rm -rf /usr/share/keyrings/postgresql.gpg
RUN rm -rf /etc/apt/sources.list.d/pgdg.list
RUN rm -rf /var/lib/apt/lists/*

# Clone the backup script
RUN git clone https://github.com/k0lter/autopostgresqlbackup.git /opt/autopostgresqlbackup
RUN rm -rf /opt/autopostgresqlbackup/.git
RUN rm -rf /opt/autopostgresqlbackup/examples
RUN rm -rf /opt/autopostgresqlbackup/services
RUN rm -rf /opt/autopostgresqlbackup/*.md
RUN rm -rf /opt/autopostgresqlbackup/Makefile

# Make script executable
RUN chmod +x /opt/autopostgresqlbackup/autopostgresqlbackup

# Copy and set Docker entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Create config folder
RUN mkdir -p /etc/autodbbackup.d/

# Create backup directory
RUN mkdir -p "/backup"
