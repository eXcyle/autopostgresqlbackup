# ---------------------------------------------------------
# Stage 1: Builder
FROM debian:trixie-slim AS builder

# Install curl, gnupg, and CA certs first
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    git

# Clone the backup script ans make executable
RUN git clone https://github.com/k0lter/autopostgresqlbackup.git /opt/autopostgresqlbackup \
&& chmod +x /opt/autopostgresqlbackup/autopostgresqlbackup

# ---------------------------------------------------------
# Stage 2: Final runtime image
FROM debian:trixie-slim

LABEL org.opencontainers.image.title="autopostgresqlbackup"
LABEL org.opencontainers.image.description="Docker container containing the AutoPostgreSQLBackup by k0lter (https://github.com/k0lter)"
LABEL org.opencontainers.image.url="https://github.com/JeroenKeizerNL/autopostgresqlbackup"
LABEL org.opencontainers.image.source="https://github.com/JeroenKeizerNL/autopostgresqlbackup"
LABEL org.opencontainers.image.documentation="https://github.com/JeroenKeizerNL/autopostgresqlbackup#readme"
LABEL org.opencontainers.image.authors="https://github.com/JeroenKeizerNL"

# Install dependencies
# Include MySQL client for MariaDB/MySQL backup support via autopostgresqlbackup
RUN apt-get update \
&& apt-get install -y --no-install-recommends \
    bash \
    gzip \
    openssl \
    tzdata \
    cron \
    mariadb-client \
    postgresql-client-17 \
&& rm -rf /var/lib/apt/lists/* \
&& rm -rf /usr/share/man/* /usr/share/doc/* /usr/share/info/* /usr/share/lintian/* /usr/share/locale/*

# Create folders
RUN mkdir -p /etc/autodbbackup.d \
&& mkdir -p "/backup" \
&& mkdir -p /opt/autopostgresqlbackup

# Copy only what's needed
COPY --from=builder /opt/autopostgresqlbackup/autopostgresqlbackup /opt/autopostgresqlbackup/autopostgresqlbackup

# Copy and set Docker entrypoint
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

HEALTHCHECK --interval=60s --timeout=10s --start-period=5s --retries=3 \
  CMD pidof cron || (echo "cron not running" && exit 1)
