# Dockerfile
FROM debian:bullseye-slim

LABEL maintainer="jeroen.keizer@outlook.com"

# Install curl, gnupg, and CA certs first
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates

RUN echo "deb http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list
RUN curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    bash \
    curl \
    gzip \
    openssl \
    tzdata \
    passwd \
    cron \
    postgresql-client-17

RUN rm -rf /var/lib/apt/lists/*

# Clone the backup script
RUN git clone https://github.com/k0lter/autopostgresqlbackup.git /opt/autopostgresqlbackup
RUN rm /opt/autopostgresqlbackup/.git -rf
RUN rm /opt/autopostgresqlbackup/examples -rf
RUN rm /opt/autopostgresqlbackup/services -rf
RUN rm /opt/autopostgresqlbackup/*.md -rf
RUN rm /opt/autopostgresqlbackup/Makefile -rf

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
