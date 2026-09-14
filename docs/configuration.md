# Configuration — référence des variables (`.env`)

Toutes sont lues à chaque boot par l'entrypoint : modifier le `.env` puis
`docker compose up -d` suffit (recréation du conteneur, volume conservé).

## Base de données

| Variable | Défaut | Effet |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | *(obligatoire)* | Mot de passe root MariaDB. |
| `MYSQL_CRON_PASSWORD` | *(obligatoire)* | User `cron` (daemons + web). Resynchronisé dans `astguiclient.conf` à chaque boot. |
| `CUSTOM_PASSWORD` | `custom1234` | User `custom`. Idem. |

Lettres/chiffres uniquement : éviter `' " \ ` et espaces (interprétés en SQL).

## Réseau et voix

| Variable | Défaut | Effet |
|---|---|---|
| `SERVER_IP` | `127.0.0.1` | IP du serveur (base + confs). Jamais de nom d'hôte. |
| `PUBLIC_IP` | *(vide = `SERVER_IP`)* | IP vue par les correspondants : `external_media/signaling_address` en `pjsip.conf`. **Sans elle derrière un NAT : audio à sens unique.** |
| `HTTP_PORT` / `HTTPS_PORT` | `80` / `443` | Ports web publiés. |
| `SIP_PORT` | `5060` | Port SIP publié (tcp+udp). |
| `RTP_START` / `RTP_END` | `10000` / `15000` | Plage RTP écrite dans `rtp.conf` (~2500 appels). |
| `RTP_RANGE` | `10000-15000` | Mapping Docker de la plage. **Doit correspondre à START/END.** |

## Comptes et fuseau

| Variable | Défaut | Effet |
|---|---|---|
| `ADMIN_PASSWORD` | *(vide)* | Mot de passe du compte admin `6666`, appliqué au **premier boot**. Vide = `1234` + alerte (à changer aussitôt). |
| `TZ` | `UTC` | Fuseau commun système + PHP (`date.timezone`) + MariaDB. Un désaccord affiche `time synchronization problem`. Ex. `Europe/Paris`. |

## Versions

| Variable | Défaut | Effet |
|---|---|---|
| `VICIDOCK_TAG` | `latest` | Tag d'image à tirer (ex. `v0.1.1`). Voir [versions](versions.md). |
| `VICIDIAL_SVN_REV` | `3939` | Rev SVN pour un **build local** (`--build`) uniquement. Ignoré avec l'image publiée. |

## TLS

Monter un vrai certificat (recommandé, indispensable pour WebRTC) :

```yaml
volumes:
  - ./mon.crt:/etc/pki/tls/certs/vicidock.crt:ro
  - ./mon.key:/etc/pki/tls/private/vicidock.key:ro
```

(À ajouter dans un fichier `docker-compose.override.yml` local.)
