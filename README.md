# Vicidock — VICIdial all-in-one sur Docker

**Une seule image** `ghcr.io/aerab243/vicidock` avec tous les services,
calquée sur **ViciBox 12.0.2**. **Un tag = une version de VICIdial.**

## Contenu de l'image

| Couche | Version |
|---|---|
| Base | AlmaLinux 9 |
| VICIdial | trunk SVN épinglé par build (`VICIDIAL_SVN_REV`) |
| Asterisk | 18.21.0-vici, ConfBridge + PJSIP |
| PHP / Web | Apache + PHP 8.2 (Remi), VICIphone 3.0 inclus |
| Base | MariaDB 10.11 (10.5 en repli) |
| Supervision | supervisord : mariadb, httpd, asterisk, crond, keepalives VICIdial |

## Démarrage rapide (image publiée)

```bash
cp .env.example .env
# éditer .env : mots de passe + SERVER_IP (IP locale ou publique)
docker compose up -d
docker compose logs -f
```

Accès : `http://localhost/vicidial/welcome.php`

Au premier démarrage, l'entrypoint initialise MariaDB, crée la base `asterisk`
+ les users `cron`/`custom`, injecte le schéma du trunk et lance `install.pl`.
Les démarrages suivants réutilisent le volume `mysql_data`.

## Build local d'une version précise

```bash
VICIDOCK_TAG=2.14-3939 VICIDIAL_SVN_REV=3939 docker compose up -d --build
```

## CI/CD

Le workflow `.github/workflows/docker-publish.yml` build et pousse l'image sur
GHCR à chaque push sur `main`, à chaque tag `v*` (ex. `v2.14-3939`) et à la
demande (`workflow_dispatch` → input `svn_rev`). Premier build : 30-60 min,
image ~2-3 Go. Aucun secret à configurer (`GITHUB_TOKEN` suffit).

## Notes importantes

- Conteneur `privileged: true` requis pour le timing DAHDI d'Asterisk.
- Plage RTP `10000-20000/udp` : à réduire dans le compose + `rtp.conf` si besoin.
- VICIphone 3.0 = softphone web servi par Apache (SIP.js) ; le WebRTC/SSL
  se termine sur le port 443.
- Docker = dev/test selon la communauté (timing haute-résolution + latence MySQL).
  ~25 agents/serveur, SSD obligatoire.
