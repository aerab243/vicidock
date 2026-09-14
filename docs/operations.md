# Opérations

## Voir l'état

```bash
docker compose ps                                        # healthy ?
docker compose logs -f                                   # tout
docker compose logs asterisk                             # n'existe pas : voir ci-dessous
docker compose exec vicidock supervisorctl status        # chaque process
wget -q -O- http://localhost/healthcheck.php             # DB + PHP
```

Tous les programmes loguent sur stdout (`docker compose logs`), y compris
MariaDB, Asterisk et chaque daemon Perl.

## Commandes utiles dans le conteneur

```bash
docker compose exec vicidock asterisk -rx "core show version"
docker compose exec vicidock asterisk -rx "sip show peers"        # chan_sip
docker compose exec vicidock asterisk -rx "pjsip show registrations"
docker compose exec vicidock asterisk -rx "rtp set debug on"      # audio ?
docker compose exec vicidock crontab -l                           # cron VICIdial
docker compose exec vicidock sh -c 'mysql -u cron -p"$MYSQL_CRON_PASSWORD" -e "SHOW TABLES IN asterisk;"'
```

## Redémarrer proprement

```bash
docker compose restart            # stop_grace_period 1 min : finit les appels
```

Ne jamais redémarrer en pleine production sans drain : un restart coupe
les appels actifs (pas de migration de canaux Asterisk). Fenêtre de
maintenance + architecture multi-serveurs VICIdial pour du zéro-downtime.

## Backup

La crontab interne lance `ADMIN_backup.pl` (2h). En plus, dump MySQL
depuis l'hôte :

```bash
docker compose exec vicidock sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers asterisk' | gzip > backup-$(date +%Y%m%d).sql.gz
```

Enregistrements : volume `recordings` (`/var/spool/asterisk/monitor`).
En prod, le passer en bind mount sur disque dédié (voir compose
`driver_opts`), jamais sur la racine.

## Dépannage (cas vus en vrai)

| Symptôme | Cause → fix |
|---|---|
| `Can't create /run/mariadb/mariadb.pid`, fail-fast au boot | Dossiers `/run/*` recréés par l'entrypoint (fixé). |
| `exit 127` sur `asterisk -V` au build | Libs partagées non copiées (staging `ldd` dans le Dockerfile). |
| Tous les `.php` en 503 | `php-fpm` manquant/arrêté : `supervisorctl status php-fpm`. |
| Daemons Perl `exit 255` socket MySQL | Démarrage parallèle : le wrapper attend MariaDB (60s). |
| `pjsip-*.conf does not exist` | Placeholders créés au boot ; le keepalive génère le contenu ensuite. |
| `chan_sip vicidial-auto lacks type` (warning) | Samples en attente de génération keepalive. Normal au boot. |
| Appel OK mais silence un sens | NAT/RTP : `PUBLIC_IP` + ports `10000-15000/udp` ouverts. `rtp set debug on`. |
| `488 Not Acceptable Here` | Codec : rester en `ulaw` des deux côtés. |
| `time synchronization problem` | `TZ` du `.env` (système+PHP+DB alignés au boot). |
| `docker-proxy: resource temporarily unavailable` au `up` | Trop de ports mappés pour la machine : réduire `RTP_RANGE`/`START`/`END` (ex. 100 ports en test). |

## Fichiers à connaître

- `/etc/astguiclient.conf` — connexion DB + `server_ip` (resync à chaque boot).
- `/etc/asterisk/pjsip.conf` — transports + externip (réécrit à chaque boot).
- `/etc/asterisk/rtp.conf`, `modules.conf` (timing) — idem.
- `/etc/my.cnf.d/vicidock.cnf` — tuning MariaDB.
- `/usr/local/share/vicidock/vicidial-crontab` — source de la crontab installée.
