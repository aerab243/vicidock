#!/bin/bash
# VICIdock entrypoint — initialise MariaDB + VICIdial au premier boot,
# réapplique la config volatile (IP, mots de passe, timezone, crontab)
# à chaque démarrage, puis rend la main à supervisord.
set -e
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD manquant}"
: "${MYSQL_CRON_PASSWORD:?MYSQL_CRON_PASSWORD manquant}"
SERVER_IP="${SERVER_IP:-127.0.0.1}"
CUSTOM_PASSWORD="${CUSTOM_PASSWORD:-custom1234}"
TZ="${TZ:-UTC}"
TRUNK=/usr/src/astguiclient/trunk
CRONTAB_SRC=/usr/local/share/vicidock/vicidial-crontab
MARKER=/var/lib/mysql/.vicidock-init-done

mkdir -p /run/mysqld /run/httpd /var/log/astguiclient /var/log/asterisk
chown -R mysql:mysql /run/mysqld /var/lib/mysql
chown apache:apache /run/httpd

# --- Fuseau horaire : système + PHP + MariaDB doivent être d'accord,
# sinon VICIdial affiche "time synchronization problem" sur chaque page.
if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
else
  echo "ATTENTION : fuseau '${TZ}' inconnu, repli sur UTC" >&2
  TZ=UTC
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi
printf 'date.timezone = %s\n' "${TZ}" > /etc/php.d/99-vicidock-timezone.ini

if [ ! -d /var/lib/mysql/mysql ]; then
  mysql_install_db --user=mysql --datadir=/var/lib/mysql --auth-root-authentication-method=normal
fi

mysqld_safe >/var/log/mariadb-init.log 2>&1 &
for _ in $(seq 1 30); do
  mysqladmin ping -h localhost --silent && break
  sleep 1
done
if ! mysqladmin ping -h localhost --silent; then
  echo "ERREUR : MariaDB n'a pas démarré (voir /var/log/mariadb-init.log) :" >&2
  tail -n 20 /var/log/mariadb-init.log >&2 || true
  exit 1
fi

ROOT_CNX=(-u root)
if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e 'SELECT 1' >/dev/null 2>&1; then
  ROOT_CNX=(-u root -p"${MYSQL_ROOT_PASSWORD}")
fi

mysql "${ROOT_CNX[@]}" <<SQL
SET GLOBAL connect_timeout=60;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS asterisk DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER IF NOT EXISTS 'cron'@'%' IDENTIFIED BY '${MYSQL_CRON_PASSWORD}';
CREATE USER IF NOT EXISTS 'cron'@'localhost' IDENTIFIED BY '${MYSQL_CRON_PASSWORD}';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'cron'@'%';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'cron'@'localhost';
GRANT RELOAD ON *.* TO 'cron'@'%';
GRANT RELOAD ON *.* TO 'cron'@'localhost';
CREATE USER IF NOT EXISTS 'custom'@'%' IDENTIFIED BY '${CUSTOM_PASSWORD}';
CREATE USER IF NOT EXISTS 'custom'@'localhost' IDENTIFIED BY '${CUSTOM_PASSWORD}';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'custom'@'%';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'custom'@'localhost';
GRANT RELOAD ON *.* TO 'custom'@'%';
GRANT RELOAD ON *.* TO 'custom'@'localhost';
FLUSH PRIVILEGES;
SQL

ROOT_CNX=(-u root -p"${MYSQL_ROOT_PASSWORD}")

# --- Premier boot : schéma + données de base + install.pl ---
if [ ! -f "$MARKER" ]; then
  if [ -z "$(mysql "${ROOT_CNX[@]}" -N -e 'SHOW TABLES IN asterisk')" ]; then
    mysql "${ROOT_CNX[@]}" asterisk < "$TRUNK/extras/MySQL_AST_CREATE_tables.sql"
  fi
  if [ -z "$(mysql "${ROOT_CNX[@]}" -N -e "SHOW TABLES IN asterisk LIKE 'servers'")" ] \
    || [ -z "$(mysql "${ROOT_CNX[@]}" -N -e 'SELECT server_ip FROM asterisk.servers LIMIT 1')" ]; then
    mysql "${ROOT_CNX[@]}" asterisk < "$TRUNK/extras/first_server_install.sql"
  fi
  if [ -f "$TRUNK/extras/upgrade_2.14.sql" ]; then
    mysql "${ROOT_CNX[@]}" asterisk < "$TRUNK/extras/upgrade_2.14.sql" 2>/dev/null || true
  fi
  if [ ! -f /etc/astguiclient.conf ]; then
    cat > /etc/astguiclient.conf <<CONF
VARDB_host => localhost
VARDB_port => 3306
VARDB_database => asterisk
VARDB_user => cron
VARDB_pass => ${MYSQL_CRON_PASSWORD}
VARDB_custom_user => custom
VARDB_custom_pass => ${CUSTOM_PASSWORD}
VARserver_ip => ${SERVER_IP}
VARactive_keepalives => 123456
VARDB_server => localhost
CONF
  fi
  cd "$TRUNK" && perl install.pl --no-prompt --copy_sample_conf_files=Y
  # Durcit l'interface manager Asterisk : locale uniquement.
  sed -i 's/0\.0\.0\.0/127.0.0.1/g' /etc/asterisk/manager.conf
  mysql "${ROOT_CNX[@]}" -e "UPDATE asterisk.servers SET asterisk_version='18.21.0-vici'" 2>/dev/null || true
  # Remplace l'IP placeholder 10.10.10.15 partout (confs + base).
  if [ -x /usr/share/astguiclient/ADMIN_update_server_ip.pl ]; then
    /usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=10.10.10.15 --server_ip="${SERVER_IP}" --auto || \
      echo "ATTENTION : ADMIN_update_server_ip.pl a échoué, vérifier l'IP serveur" >&2
    cd "$TRUNK" && perl install.pl --no-prompt || \
      echo "ATTENTION : régénération des confs après changement d'IP incomplète" >&2
  fi
  if [ -x /usr/share/astguiclient/ADMIN_area_code_populate.pl ]; then
    /usr/share/astguiclient/ADMIN_area_code_populate.pl || \
      echo "ATTENTION : ADMIN_area_code_populate.pl a échoué (relançable à la main)" >&2
  fi
  touch "$MARKER"
fi

# --- Appliqué à chaque boot (volumes persistants, .env modifiable) ---
sed -i "s|^VARserver_ip.*|VARserver_ip => ${SERVER_IP}|" /etc/astguiclient.conf
sed -i "s|^VARDB_pass.*|VARDB_pass => ${MYSQL_CRON_PASSWORD}|" /etc/astguiclient.conf
sed -i "s|^VARDB_custom_pass.*|VARDB_custom_pass => ${CUSTOM_PASSWORD}|" /etc/astguiclient.conf
mysql "${ROOT_CNX[@]}" -e "UPDATE asterisk.servers SET server_ip='${SERVER_IP}'" 2>/dev/null || true

if [ -f "$CRONTAB_SRC" ]; then
  crontab "$CRONTAB_SRC"
else
  echo "ATTENTION : crontab introuvable ($CRONTAB_SRC), tâches planifiées VICIdial inactives" >&2
fi

if [ ! -f /etc/pki/tls/certs/vicidock.crt ]; then
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout /etc/pki/tls/private/vicidock.key \
    -out /etc/pki/tls/certs/vicidock.crt \
    -subj "/CN=${SERVER_IP}"
fi
sed -i 's|^SSLCertificateFile .*|SSLCertificateFile /etc/pki/tls/certs/vicidock.crt|; s|^SSLCertificateKeyFile .*|SSLCertificateKeyFile /etc/pki/tls/private/vicidock.key|' /etc/httpd/conf.d/ssl.conf

mysqladmin "${ROOT_CNX[@]}" shutdown
for _ in $(seq 1 30); do
  mysqladmin ping -h localhost --silent 2>/dev/null || break
  sleep 1
done

exec /usr/bin/supervisord -n -c /etc/supervisord.conf
