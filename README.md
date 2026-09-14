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
| PHP / Web | Apache + PHP 8.2 (Remi), réglages VICIdial + `date.timezone` via `$TZ`, VICIphone 3.0 inclus, TLS auto-signé |
| Perl | Modules CPAN requis par VICIdial (Net::Telnet, Proc::ProcessTable, Spreadsheet::*, Mail::*, etc.) |
| Mail | sendmail local (notifications/voicemails) |
| Tâches planifiées | Crontab VICIdial complète (`docker/vicidial-crontab` : hopper, keepalive, mixage MP3, optimisations DB) |
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
surveille la page d'accueil.

## Premier login et premier appel (10 min)

Login par défaut : `6666` / `1234` — **à changer aussitôt**
(Admin > Users > 6666). L'entrypoint charge déjà le schéma, les données
de base (`first_server_install.sql`), les indicatifs (`area codes`),
la crontab et cale l'IP (`SERVER_IP`) partout.

1. Admin > Servers : vérifier timezone et IP (`SERVER_IP` du `.env`).
2. Admin > Carriers : ajouter le trunk SIP du provider (codec `ulaw`
   pour commencer), vérifier `asterisk -rx "pjsip show registrations"`.
3. Admin > Campaigns : créer `TEST01` (dial `RATIO`, niveau `1.0`).
4. Admin > Lists : créer une liste rattachée à `TEST01`, y charger
   quelques leads (`phone_code`, `phone_number`, nom).
5. Admin > Users + Admin > Phones : créer l'agent et son poste SIP.
6. Interface agent : `https://<serveur>/agc/vicidial.php` → login,
   campagne `TEST01`, Resume.

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
- Timezone : `TZ` dans le `.env` (système + PHP + MariaDB alignés
  automatiquement). Un désaccord affiche `time synchronization problem`.
- Pare-feu hôte (ex. firewalld) : ouvrir `5060/tcp+udp` (SIP),
  `10000-20000/udp` (RTP), `80/443/tcp` (web). Sans audio = presque
  toujours RTP bloqué ou NAT : renseigner `externip`/`localnet` dans
  la conf SIP Asterisk.
- Codecs : commencer en `ulaw` (G.711) des deux côtés ; une erreur
  `488 Not Acceptable Here` = désaccord de codec avec le provider.
- `manager.conf` est restreint à `127.0.0.1` au premier boot.
- Correspondance avec le guide ViciStack (méthode 3 Docker) : une seule
  image ici au lieu de 3 conteneurs, MariaDB non exposée, et **pas de
  `privileged` ni de DAHDI kernel** — le timing passe par timerfd via
  ConfBridge (le moteur moderne de VICIdial, MeetMe étant historique).
- Docker = dev/test selon la communauté (timing haute-résolution + latence MySQL).
  ~25 agents/serveur, SSD obligatoire.
