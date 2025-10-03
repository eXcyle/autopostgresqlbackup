# Dockerfile
FROM alpine:latest

LABEL maintainer="jeroen.keizer@outlook.com"
ENV BACKUPDIR="/backups"

# Install dependencies
RUN apk add --no-cache \
    postgresql-client \
    git \
    bash \
    curl \
    gzip \
    openssl \
    tzdata \
    shadow \
    cronie

# Clone the backup script
RUN git clone https://github.com/k0lter/autopostgresqlbackup.git /opt/autopostgresqlbackup

# Make script executable
RUN chmod +x /opt/autopostgresqlbackup/autopostgresqlbackup

# Copy and set Docker entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Create config folder
RUN mkdir -p /etc/autodbbackup.d/

# Create backup directory
RUN mkdir -p $BACKUPDIR

# Add cron job
RUN echo "0 2 * * * /opt/autopostgresqlbackup/autopostgresqlbackup" >> /etc/crontabs/root
