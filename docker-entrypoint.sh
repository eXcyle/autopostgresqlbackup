#!/bin/bash
set -e

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
#  If CRON_SCHEDULE is defined, use this value, otherwise use a default
if [ "${CRON_SCHEDULE}" ]; then
    echo "Configuring schedule in /etc/crontab for ${CRON_SCHEDULE}..."
else
    CRON_SCHEDULE="0 2 * * *"
    echo "Configuring schedule in /etc/crontab for dafault crontab running daily at 02:00..."
fi
  
# Create the crontab file
cat <<-EOF > /etc/crontab

SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# m h dom mon dow user command
${CRON_SCHEDULE} root /opt/autopostgresqlbackup/autopostgresqlbackup    
EOF

# Create the postgresql password file
echo "Creating postgresql password file..."
cat <<-EOF > /root/.pgpass

${PG_DBHOST:-localhost}:*:*:${PG_USERNAME:-postgres}:${PASSPHRASE}
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

# Define default values for selected keys
declare -A DEFAULTS=(
  [MAILADDR]=""
  [DBENGINE]="postgresql"
  [SU_USERNAME]=""
  [BACKUPDIR]="/backup"
  [DBNAMES]="all"
  [CREATE_DATABASE]="yes"
  [DOWEEKLY]=7
  [DOMONTHLY]=1
  [BRDAILY]=14
  [BRWEEKLY]=5
  [BRMONTHLY]=12
  [COMP]="gzip"
  [PERM]=600
)

# Define blacklist (uppercase for consistency)
declare -A BLACKLIST=(
  [MAILADDR]=1
  [DBENGINE]=1
  [SU_USERNAME]=1
  [BACKUPDIR]=1
  [PGDUMP]=1
  [PGDUMPALL]=1
  [PGDUMP_OPTS]=1
  [PGDUMPALL_OPTS]=1
  [MY]=1
  [MYDUMP]=1
  [MYDUMP_OPTS]=1
  [PREBACKUP]=1
  [POSTBACKUP]=1
)

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG_PATH")"
> "$CONFIG_PATH"

# Write default values with PG_ override support
for key in "${!DEFAULTS[@]}"; do
  env_key="PG_${key}"
  value="${!env_key:-${DEFAULTS[$key]}}"
  echo "${key}=\"${value}\"" >> "$CONFIG_PATH"
done

# Write additional PG_ variables not in defaults or blacklist
env | grep '^PG_' | while IFS='=' read -r raw_key value; do
  stripped="${raw_key#PG_}"
  upper="${stripped^^}"

  # Skip if already handled or blacklisted
  if [[ -n "${DEFAULTS[$upper]}" || -n "${BLACKLIST[$upper]}" ]]; then
    continue
  fi

  echo "${upper}=\"${value}\"" >> "$CONFIG_PATH"
done

echo "Config written to $CONFIG_PATH"
echo "Current Config :"
cat $CONFIG_PATH

echo " "
echo "Done setting up..."

# set /etc/environment for cron
printenv > /etc/environment

# Execute cron with parameters (autopostgresql script is under /etc/cron.daily)
echo " "
echo "Execute cron service..."
exec crond -f

