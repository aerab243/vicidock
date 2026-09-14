# Vicidock — VICIdial all-in-one sur Docker

**Une seule image** `ghcr.io/aerab243/vicidock` avec tous les services,
calquée sur **ViciBox 12.0.2**. **Un tag = une version de VICIdial.**

## Contenu de l'image

| Couche | Version |
|---|---|
| Base | AlmaLinux 9 |
| VICIdial | trunk SVN épinglé, rev **3939** par défaut (`VICIDIAL_SVN_REV`) |
| Asterisk | 18.21.0-vici, ConfBridge + PJSIP (checksum SHA256 vérifié au build) |
| Timing | timerfd via ConfBridge (pas de module kernel DAHDI en conteneur) |
| PHP / Web | Apache + PHP 8.2 (Remi), VICIphone 3.0 inclus, TLS auto-signé |
| Base | MariaDB 10.11 (10.5 en repli), non exposée hors conteneur |
| Supervision | supervisord : mariadb, httpd, asterisk, crond, keepalives VICIdial |

## Démarrage rapide (image publiée)

```bash
cp .env.example .env
# éditer .env : mots de passe + SERVER_IP (IP locale ou publique)
docker compose up -d
docker compose logs -f
```

Accès : `https://localhost/vicidial/welcome.php` (certificat auto-signé au
premier boot — remplacez-le par un vrai cert en montant vos fichiers sur
`/etc/pki/tls/certs/vicidock.crt` et `/etc/pki/tls/private/vicidock.key`).

Au premier démarrage, l'entrypoint initialise MariaDB, crée la base `asterisk`
+ les users `cron`/`custom`, injecte le schéma du trunk et lance `install.pl`.
Les démarrages suivants réutilisent le volume `mysql_data`. Un healthcheck
redémarre le conteneur si la page d'accueil ne répond plus.

## Build local d'une version précise

```bash
VICIDOCK_TAG=2.14-3939 VICIDIAL_SVN_REV=3939 docker compose up -d --build
```

## CI/CD

Le workflow `.github/workflows/docker-publish.yml` :
- build sur push `main`, tags `v*`, **rebuild mensuel** (patchs Alma/Remi),
  et manuel (`workflow_dispatch` → `svn_rev`)
- **scan Trivy : publication bloquée si CVE critique**
- push GHCR si tout est vert (tags `latest`, version, sha)

Premier build : 30-60 min, image ~2-3 Go. Aucun secret à configurer
(`GITHUB_TOKEN` suffit).

## Durcissement appliqué

- SHA256 vérifié pour chaque source à version fixe (Asterisk, libs…)
- **Pas de `privileged`** : aucun module kernel en conteneur, timing par timerfd
- `no-new-privileges`, `pids_limit`, `/tmp` et `/run` en tmpfs
- MySQL joignable uniquement dans le conteneur (port 3306 non publié)
- `.dockerignore` : le contexte de build n'embarque ni `.git` ni `.env`

## Notes importantes

- Plage RTP `10000-20000/udp` : à réduire dans le compose + `rtp.conf` si besoin.
- VICIphone 3.0 = softphone web servi par Apache (SIP.js) en WebRTC sur le 443.
- Docker = dev/test selon la communauté (timing haute-résolution + latence MySQL).
  ~25 agents/serveur, SSD obligatoire.
