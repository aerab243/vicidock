# Installation

## Prérequis

- Docker récent avec le plugin Compose (`docker compose version`).
- ~4 Go de RAM libres, SSD **obligatoire** (charge MySQL + enregistrements).
- Ports : `80` + `443` (web), `5060/tcp+udp` (SIP), `10000-15000/udp` (RTP).
  Tous pilotables par variables, voir [configuration](configuration.md).
- ~25 agents max par conteneur (préconisation communauté, usage dev/test).

## Pas à pas

```bash
git clone https://github.com/aerab243/vicidock.git && cd vicidock
cp .env.example .env
```

Éditer `.env` au minimum : `MYSQL_ROOT_PASSWORD`, `MYSQL_CRON_PASSWORD`,
`ADMIN_PASSWORD`, `SERVER_IP` (IP locale ou publique du serveur — jamais un
nom d'hôte). Derrière un NAT, ajouter `PUBLIC_IP` (défaut = `SERVER_IP`).
Référence complète : [configuration](configuration.md).

```bash
docker compose pull     # image publiée (2-3 Go la première fois)
docker compose up -d
docker compose logs -f  # suivre le premier boot (~5-10 min)
```

## Ce que fait le premier boot

1. MariaDB initialisée (base `asterisk`, users `cron`/`custom`).
2. Schéma + données de base (`first_server_install.sql`) + indicatifs.
3. `install.pl`, IP propagée partout (`ADMIN_update_server_ip.pl`),
   externip SIP/RTP + réseaux locaux, plage RTP, timing timerfd.
4. Mot de passe admin `6666` = `ADMIN_PASSWORD` (ou `1234` + alerte si vide).
5. Certificat TLS auto-signé, crontab VICIdial, démarrage supervisé.

Les boots suivants réutilisent le volume `mysql_data` et réappliquent la
config volatile (IP, mots de passe, timezone, crontab).

## Vérifier que tout tourne

```bash
docker compose ps                                        # healthy attendu
wget -q -O- http://localhost/healthcheck.php             # {"status":"healthy",...}
docker compose exec vicidock supervisorctl status
docker compose exec vicidock asterisk -rx "core show version"
```

Puis `https://<serveur>/vicidial/welcome.php` (accepter le cert auto-signé),
login `6666`. Suite : [premier appel](premier-appel.md).

## Cohabitation avec d'autres stacks

Si 80/443/5060 sont pris, surcharger dans le `.env` (jamais d'override) :

```
HTTP_PORT=8080
HTTPS_PORT=8443
SIP_PORT=5062
```

En local avec peu de RAM/process, réduire aussi la plage RTP :
`RTP_RANGE=10000-10099`, `RTP_START=10000`, `RTP_END=10099`.

## Recommencer de zéro

```bash
docker compose down -v   # efface aussi la base : rejoue le premier boot
```
