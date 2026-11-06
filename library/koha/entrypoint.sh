#!/bin/bash
# Container entrypoint: (re)creates the Koha instance config from environment
# variables on every start, installs the database on the first start, then runs
# Apache in the foreground. All durable state lives in MariaDB and /var/lib/koha.
set -euo pipefail

INST="${KOHA_INSTANCE:-library}"
DB_HOST="${KOHA_DB_HOST:-db}"
DB_NAME="${KOHA_DB_NAME:-koha_library}"
DB_USER="${KOHA_DB_USER:-koha_library}"
: "${KOHA_DB_PASS:?KOHA_DB_PASS is required}"
: "${KOHA_ADMIN_PASS:?KOHA_ADMIN_PASS is required}"
STAFF_PORT=8081
export TZ="${TZ:-UTC}"

log() { echo "[koha-init] $*"; }

# --- 1. memcached (Koha caches sysprefs and sessions in it) -----------------
memcached -u memcache -m 64 -d
cron

# --- 2. wait for MariaDB ----------------------------------------------------
log "waiting for database at $DB_HOST..."
for i in $(seq 1 120); do
    mariadb -h "$DB_HOST" -u "$DB_USER" -p"$KOHA_DB_PASS" "$DB_NAME" -e 'select 1' >/dev/null 2>&1 && break
    [ "$i" = 120 ] && { log "database never became ready"; exit 1; }
    sleep 2
done

# --- 3. instance config (regenerated each time a container is created) ------
if [ ! -d "/etc/koha/sites/$INST" ]; then
    log "creating Koha instance '$INST'..."
    sed -i \
        -e 's|^DOMAIN=.*|DOMAIN=""|' \
        -e 's|^INTRASUFFIX=.*|INTRASUFFIX=""|' \
        -e "s|^INTRAPORT=.*|INTRAPORT=\"$STAFF_PORT\"|" \
        /etc/koha/koha-sites.conf
    echo "$INST:$DB_USER:$KOHA_DB_PASS:$DB_NAME:$DB_HOST" > /etc/koha/passwd
    koha-create --use-db --dbhost "$DB_HOST" --timezone "$TZ" \
        --memcached-servers 127.0.0.1:11211 "$INST" 2>&1 | grep -v AH00558 || true

    # No RabbitMQ in this stack: workers fall back to polling the database.
    CONF="/etc/koha/sites/$INST/koha-conf.xml"
    perl -0pi -e 's|\s*<message_broker>.*?</message_broker>||s' "$CONF"

    # Serve both interfaces through Plack (much faster than plain CGI).
    SITE="/etc/apache2/sites-available/$INST.conf"
    sed -i \
        -e 's|^\(\s*\)Include /etc/koha/apache-shared-opac.conf|\1Include /etc/koha/apache-shared-opac-plack.conf|' \
        -e 's|^\(\s*\)Include /etc/koha/apache-shared-intranet.conf|\1Include /etc/koha/apache-shared-intranet-plack.conf|' \
        -e 's|^#\s*Include /etc/koha/apache-shared-opac-plack.conf||' \
        -e 's|^#\s*Include /etc/koha/apache-shared-intranet-plack.conf||' "$SITE"
    koha-plack --enable "$INST" >/dev/null 2>&1 || true   # koha-create may already have enabled it

    # Run Apache itself as the instance user instead of mpm_itk's per-vhost
    # uid switching (which needs extra capabilities and is pointless here:
    # Plack does the real work as that user already).
    sed -i '/AssignUserID/d' "$SITE"
    sed -i -e "s/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=$INST-koha/" \
           -e "s/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=$INST-koha/" /etc/apache2/envvars
    grep -q "^Listen $STAFF_PORT\b" /etc/apache2/ports.conf || echo "Listen $STAFF_PORT" >> /etc/apache2/ports.conf
    grep -q '^ServerName' /etc/apache2/apache2.conf || echo 'ServerName localhost' >> /etc/apache2/apache2.conf
fi
chown -R "$INST-koha:$INST-koha" "/var/lib/koha/$INST" "/var/log/koha/$INST" 2>/dev/null || true

# --- 4. install or upgrade the database -------------------------------------
TABLES=$(mariadb -N -h "$DB_HOST" -u "$DB_USER" -p"$KOHA_DB_PASS" "$DB_NAME" \
    -e "select count(*) from information_schema.tables where table_schema='$DB_NAME'")
if [ "$TABLES" = "0" ]; then
    log "first start: installing Koha (about a minute)..."
    # (not koha-shell -c: it wraps the command in single quotes of its own)
    runuser -u "$INST-koha" -- env \
        KOHA_CONF="/etc/koha/sites/$INST/koha-conf.xml" \
        KOHA_ADMIN_USER="${KOHA_ADMIN_USER:-admin}" KOHA_ADMIN_PASS="$KOHA_ADMIN_PASS" \
        KOHA_LIBRARY_NAME="${KOHA_LIBRARY_NAME:-My Library}" TZ="$TZ" \
        perl /opt/koha-init/bootstrap.pl
    TABLES=$(mariadb -N -h "$DB_HOST" -u "$DB_USER" -p"$KOHA_DB_PASS" "$DB_NAME" \
        -e "select count(*) from information_schema.tables where table_schema='$DB_NAME'")
    [ "$TABLES" -gt 0 ] || { log "ERROR: installation did not create the database"; exit 1; }
    FIRST_RUN=1
else
    log "existing database found - applying any pending upgrades..."
    koha-upgrade-schema "$INST" || log "WARNING: koha-upgrade-schema reported a problem (see output above)"
    FIRST_RUN=0
fi

# --- 5. background services (their `daemon` processes die with the container,
#        so they are started explicitly on every start) ------------------------
if [ "$FIRST_RUN" = 1 ] || [ ! -e "/var/lib/koha/$INST/biblios/register" ]; then
    log "building search index..."
    koha-rebuild-zebra -f -v "$INST" >/dev/null 2>&1 || true
fi
for svc in koha-zebra koha-indexer koha-worker koha-plack; do
    "$svc" --restart "$INST" >/dev/null 2>&1 || "$svc" --start "$INST" >/dev/null 2>&1 \
        || log "WARNING: could not start $svc"
done

# koha-create / koha-plack may have started Apache already; run it in the foreground instead.
apache2ctl -k stop >/dev/null 2>&1 || true
for i in 1 2 3 4 5; do pgrep -x apache2 >/dev/null || break; sleep 1; done
rm -f /var/run/apache2/apache2.pid

log "ready - library catalogue on :80, staff interface on :$STAFF_PORT"
exec apache2ctl -D FOREGROUND
