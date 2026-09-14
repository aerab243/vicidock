# Architecture

## Une seule image, trois stages

```
builder   : Development Tools + jansson/lame/libsrtp + Asterisk 18.21.0-vici
            + asterisk-perl + staging des libs partagées (ldd)
perldeps  : modules CPAN absents/cassés d'EPEL9 (Spreadsheet, HTML::Tree…),
            recopiés via PERL5LIB
runtime   : AlmaLinux 9 + MariaDB 10.11 + Apache/PHP 8.2 + Perl + VICIdial
            trunk SVN + sons + crontab + confs → supervisord
```

Le multi-stage jette les ~2 Go d'outils de build ; l'image fait ~2-3 Go.

## Au boot (entrypoint)

Init MariaDB → users SQL → **premier boot uniquement** : schéma, seed
(`first_server_install.sql`), `upgrade_2.14.sql`, `install.pl`,
`manager.conf` local, `ADMIN_update_server_ip.pl`, `install.pl` à nouveau,
area codes, `ADMIN_PASSWORD` → **chaque boot** : resync IP/mots de passe,
timezone (système+PHP), externip/localnet `pjsip`, RTP, timing, placeholders
d'includes, crontab, TLS auto-signé → `mysqld shutdown` → supervisord.

## Supervision

`mariadb` (10) → `php-fpm` (15) → `httpd` (20) → `asterisk` (30) →
`crond` (40) → 5 daemons Perl (50-54, via wrapper d'attente DB).
La crontab (`ADMIN_keepalive_ALL.pl`) reste en filet de sécurité.

## Choix assumés (vs guides ViciStack)

- **All-in-one** au lieu de 3 conteneurs : simplicité > scaling (~25 agents).
- **Pas de `privileged`, pas de DAHDI kernel** : timing par `timerfd` via
  ConfBridge (moteur moderne ; MeetMe est historique).
- **Bridge + externip**, pas de `network_mode: host` : compatible PaaS
  (Dokploy/Openship), au prix d'une config NAT rigoureuse.
- **MariaDB 10.11**, pas MySQL 8 (auth des vieux clients) ; schéma rev 3898+
  immunisé contre le bug TIMESTAMP de ViciBox 12.
- **`chan_sip`** (template `SIP_generic` historique), `res_pjsip` prêt pour
  WebRTC (websocket + srtp compilés).
- MySQL non exposée, `manager.conf` en `127.0.0.1`, `no-new-privileges`,
  `/tmp`+`/run` en tmpfs, SHA256 vérifiés au build, Trivy bloquant en CI.
