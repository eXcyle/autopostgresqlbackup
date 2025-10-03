#!/bin/bash

# Logic for Password file required
#  If PG_PASSWORD_SECRET env var is defined, search for the /run/secrets/${PASSWORD_SECRET} and read the content
#  If PG_PASSWORD_SECRET is not defined, use PASSWORD env variable
# The idea, as specified in the software:
#   create a file /root/.pgpass containing a line like this 
#           hostname:*:*:dbuser:dbpass
# replace hostname with the value of DBHOST and postgres with
# the value of USERNAME
PASSPHRASE=""
if [ "${PG_PASSWORD_SECRET}" ]; then
    echo "Using docker secrets..."
    if [ -f "/run/secrets/${PG_PASSWORD_SECRET}" ]; then
        PASSPHRASE=$(cat /run/secrets/${PG_PASSWORD_SECRET})
    else
        echo "ERROR: Secret file not found in /run/secrets/${PG_PASSWORD_SECRET}"
        echo "Please verify your docker secrets configuration."
        exit 1
    fi
else
    echo "Using environment password..."
    PASSPHRASE=${PG_PASSWORD}
fi

# Logic for the CRON schedule
#  If CRON_SCHEDULE is defined, delete the script under cron.daily and copy this one to crontab
#  If CRON_SCHEDULE is not defined, don't do anything, use default cron.daily behaviour
if [ "${PG_CRON_SCHEDULE}" ]; then
  echo "Configuring a CUSTOM SCHEDULE in /etc/crontab for ${PG_CRON_SCHEDULE} ..."
    # Create the crontab file
cat <<-EOF > /etc/crontab

SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# m h dom mon dow user command
${CRON_SCHEDULE} root /opt/autopostgresqlbackup/autopostgresqlbackup    
EOF
else
    echo "Using cron.daily schedule..."
fi

# Create the file
echo "Creating the password file..."
cat <<-EOF > /root/.pgpass

${PG_DBHOST:-localhost}:*:*:${PG_USERNAME:-postgres}:${PG_PASSPHRASE}
EOF
# Permissions for this file shoudl be set to 0600
chmod 0600 /root/.pgpass

# Set timezone if set
if [ ! -z "${TZ}" ]; then
    echo "Setting timezone to ${TZ}"
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
fi

# Generate configfile by using PG_ docker variables
CONFIG_PATH="/etc/autodbbackup.d/autopostgresqlbackup.conf"
BLACKLIST=("MAILADDR" "DBENGINE" "SU_USERNAME" "BACKUPDIR" "PGDUMP" "PGDUMPALL" "PGDUMP_OPTS" "PGDUMPALL_OPTS" "MY" "MYDUMP" "MYDUMP_OPTS" "PREBACKUP" "POSTBACKUP")

> "$CONFIG_PATH"
echo "MAILADDR=\"\"" >> "$CONFIG_PATH"
echo "DBENGINE=\"postgresql\"" >> "$CONFIG_PATH"
echo "SU_USERNAME=\"\"" >> "$CONFIG_PATH"
echo "BACKUPDIR=\"/backup\"" >> "$CONFIG_PATH"

# Loop through all PG_* environment variables
env -0 | grep '^PG_' | while IFS='=' read -r key value; do
    stripped_key="${key#PG_}"
    upper_key="${stripped_key^^}"

    # Check if stripped key is in blacklist
    skip=false
    for blocked in "${BLACKLIST[@]}"; do
        if [[ "${upper_key}" == "${blocked^^}" ]]; then
            skip=true
            break
        fi
    done

    # Write to config if not blacklisted
    if ! $skip; then
        echo "${upper_key}=\"${value}\"" >> "$CONFIG_PATH"
    fi
done
echo "Config written to $CONFIG_PATH"

# set /etc/environment for cron
printenv > /etc/environment

# Execute cron with parameters (autopostgresql script is under /etc/cron.daily)
echo "Execute cron service..."
exec crond -f

