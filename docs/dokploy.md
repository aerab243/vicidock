# Déployer sur Dokploy / Openship (et PaaS Docker)

L'image publiée rend ça simple : **pas de build**, on déploie
`ghcr.io/aerab243/vicidock:<tag>` (paquet public, voir [versions](versions.md)).

## Principe

- **Web (80/443) via le reverse-proxy** du PaaS (Traefik/OpenResty) avec
  TLS Let's Encrypt automatique → parfait pour l'admin, et plus tard
  WebRTC (micro exige un cert reconnu).
- **VoIP en direct, hors proxy HTTP** : `5060/tcp+udp` (ou `SIP_PORT`) et
  la plage RTP (`RTP_RANGE`) publiés en ports bruts.
- `SERVER_IP` (ou `PUBLIC_IP` derrière NAT) = IP publique du nœud.
- Volumes persistants : base + enregistrements.
- Single-node uniquement (volumes locaux + plage UDP).

## Avec Dokploy

Application de type **Compose** : coller le `docker-compose.yml` (ou
pointer le repo), renseigner les variables d'environnement (mêmes noms
que le `.env`), attacher un domaine au port 80. Mapper les ports
SIP/RTP en direct.

## Avec Openship

Même schéma (fichier compose déployé tel quel). Bonus Openship : builds
hors prod inutiles ici puisque l'image est prébuild ; adoption possible
d'un conteneur existant.

## Limites connues

- Plage RTP 5000 ports : lourde mais faisable sur un vrai VPS ; réduire
  (`RTP_RANGE` + `RTP_START`/`END`) si besoin.
- Pas de multi-nœuds :caler ~25 agents/serveur, puis cluster VICIdial
  natif (Admin > Servers) pour scaler.
- WebRTC navigateur : chantier en cours (port 8089, `http.conf`, cert
  valide) — voir roadmap.
