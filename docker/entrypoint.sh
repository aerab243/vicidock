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

mkdir -p /run/mysqld /run/mariadb /run/httpd /run/asterisk /var/log/astguiclient /var/log/asterisk /var/log/mysql /var/log/mariadb
chown -R mysql:mysql /run/mysqld /run/mariadb /var/lib/mysql /var/log/mysql /var/log/mariadb
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
  echo "ERREUR : MariaDB n'a pas démarré." >&2
  echo "--- /var/log/mariadb/mariadb.log (daemon) ---" >&2
  tail -n 20 /var/log/mariadb/mariadb.log >&2 || true
  echo "--- /var/log/mariadb-init.log (mysqld_safe) ---" >&2
  tail -n 5 /var/log/mariadb-init.log >&2 || true
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
  if [ -n "${ADMIN_PASSWORD:-}" ]; then
    mysql "${ROOT_CNX[@]}" -e "UPDATE asterisk.vicidial_users SET pass='${ADMIN_PASSWORD}' WHERE user='6666'" && \
      echo "Mot de passe admin (6666) défini depuis ADMIN_PASSWORD." || \
      echo "ATTENTION : mot de passe admin non appliqué" >&2
  else
    echo "ATTENTION : ADMIN_PASSWORD vide, le login 6666/1234 reste actif — changez-le aussitôt" >&2
  fi
  touch "$MARKER"
fi

# --- Appliqué à chaque boot (volumes persistants, .env modifiable) ---
sed -i "s|^VARserver_ip.*|VARserver_ip => ${SERVER_IP}|" /etc/astguiclient.conf
sed -i "s|^VARDB_pass.*|VARDB_pass => ${MYSQL_CRON_PASSWORD}|" /etc/astguiclient.conf
sed -i "s|^VARDB_custom_pass.*|VARDB_custom_pass => ${CUSTOM_PASSWORD}|" /etc/astguiclient.conf
mysql "${ROOT_CNX[@]}" -e "UPDATE asterisk.servers SET server_ip='${SERVER_IP}'" 2>/dev/null || true

# --- Voix/NAT : externip + réseaux locaux (chaque boot) ---
# Sans externip correct, le RTP part vers une IP privée = audio à sens unique.
PUBLIC_IP="${PUBLIC_IP:-$SERVER_IP}"
python3 - "$PUBLIC_IP" <<'PYEOF' || echo "ATTENTION : config NAT pjsip non appliquée" >&2
import sys
path = '/etc/asterisk/pjsip.conf'
ext_ip = sys.argv[1]
local_nets = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']
wanted = {
    'external_media_address': ext_ip,
    'external_signaling_address': ext_ip,
}
try:
    with open(path) as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []
out, cur, seen = [], None, set()
def emit(section):
    for key in ('external_media_address', 'external_signaling_address'):
        if (section, key) not in seen:
            out.append('%s = %s\n' % (key, wanted[key]))
    if (section, 'local_net') not in seen:
        for net in local_nets:
            out.append('local_net = %s\n' % net)
for line in lines + [None]:
    stripped = line.strip() if line is not None else ''
    if line is None or (stripped.startswith('[') and stripped.endswith(']')):
        if cur in ('transport-udp', 'transport-tcp'):
            emit(cur)
        if line is None:
            break
        cur = stripped[1:-1]
        seen = set()
        out.append(line)
        continue
    if cur in ('transport-udp', 'transport-tcp') and '=' in stripped \
            and not stripped.startswith((';', '#')):
        key = stripped.split('=', 1)[0].strip()
        if key in wanted:
            out.append('%s = %s\n' % (key, wanted[key]))
            seen.add((cur, key))
            continue
        if key == 'local_net':
            if (cur, key) not in seen:
                for net in local_nets:
                    out.append('local_net = %s\n' % net)
                seen.add((cur, key))
            continue
    out.append(line)
present = {l.strip()[1:-1] for l in out
           if l.strip().startswith('[') and l.strip().endswith(']')}
for section in ('transport-udp', 'transport-tcp'):
    if section not in present:
        proto = section.split('-')[1]
        out.append('\n[%s]\ntype = transport\nprotocol = %s\nbind = 0.0.0.0:5060\n'
                   % (section, proto))
        out.append('external_media_address = %s\nexternal_signaling_address = %s\n'
                   % (ext_ip, ext_ip))
        for net in local_nets:
            out.append('local_net = %s\n' % net)
with open(path, 'w') as f:
    f.writelines(out)
PYEOF

# Plage RTP alignée avec le compose (2500 appels simultanés max).
if grep -q '^rtpstart' /etc/asterisk/rtp.conf 2>/dev/null; then
  sed -i 's/^rtpstart.*/rtpstart = 10000/; s/^rtpend.*/rtpend = 15000/' /etc/asterisk/rtp.conf
elif [ -f /etc/asterisk/rtp.conf ]; then
  printf '\nrtpstart = 10000\nrtpend = 15000\n' >> /etc/asterisk/rtp.conf
fi

# Timing : timerfd en conteneur (pas de module kernel DAHDI possible).
for directive in 'noload => res_timing_dahdi.so' 'load => res_timing_timerfd.so' 'noload => chan_dahdi.so'; do
  grep -qF "$directive" /etc/asterisk/modules.conf 2>/dev/null || \
    sed -i "/^\\[modules\\]/a $directive" /etc/asterisk/modules.conf
done

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
