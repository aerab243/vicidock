#!/bin/bash
set -e
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD manquant}"
: "${MYSQL_CRON_PASSWORD:?MYSQL_CRON_PASSWORD manquant}"
SERVER_IP="${SERVER_IP:-127.0.0.1}"
CUSTOM_PASSWORD="${CUSTOM_PASSWORD:-custom1234}"
TRUNK=/usr/src/astguiclient/trunk
MARKER=/var/lib/mysql/.vicidock-init-done

mkdir -p /run/mysqld /var/log/astguiclient
chown -R mysql:mysql /run/mysqld /var/lib/mysql
modprobe dahdi_dummy 2>/dev/null || true

if [ ! -d /var/lib/mysql/mysql ]; then
  mysql_install_db --user=mysql --datadir=/var/lib/mysql --auth-root-authentication-method=normal
fi

mysqld_safe >/var/log/mariadb-init.log 2>&1 &
for i in $(seq 1 30); do
  mysqladmin ping -h localhost --silent && break
  sleep 1
done

ROOT_CNX=(-u root)
if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e 'SELECT 1' >/dev/null 2>&1; then
  ROOT_CNX=(-u root -p"${MYSQL_ROOT_PASSWORD}")
fi

mysql "${ROOT_CNX[@]}" <<SQL
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

if [ ! -f "$MARKER" ]; then
  if [ -z "$(mysql "${ROOT_CNX[@]}" -N -e 'SHOW TABLES IN asterisk')" ]; then
    mysql "${ROOT_CNX[@]}" asterisk < "$TRUNK/extras/MySQL_AST_CREATE_tables.sql"
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
  touch "$MARKER"
fi

sed -i "s|^VARserver_ip.*|VARserver_ip => ${SERVER_IP}|" /etc/astguiclient.conf
mysql "${ROOT_CNX[@]}" -e "UPDATE asterisk.servers SET server_ip='${SERVER_IP}'" 2>/dev/null || true

mysqladmin "${ROOT_CNX[@]}" shutdown
for i in $(seq 1 30); do
  mysqladmin ping -h localhost --silent 2>/dev/null || break
  sleep 1
done

exec /usr/bin/supervisord -n -c /etc/supervisord.conf
