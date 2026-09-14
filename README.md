# Vicidock — VICIdial basé sur Docker

Base minimale pour faire tourner VICIdial avec des images Docker pré-définies.

## Services

- `vicidial-db` : `mariadb:10.11` (image officielle, base `asterisk`)
- `vicidial` : `ahroniy/vicidial:latest` (image communautaire, ~1.2 GB)

> Il n'existe pas d'image Docker officielle VICIdial / ViciBox.
> `ahroniy/vicidial` est pratique pour démarrer mais non documentée
> et mise à jour il y a plus d'un an. Pour la production,
> prévoir de construire ses propres images (AlmaLinux 9 + Asterisk 18 + DAHDI).

## Démarrage

```bash
cp .env.example .env
# éditer .env (mots de passe + SERVER_IP = IP locale ou publique)
docker compose up -d
docker compose logs -f
```

Accès : `http://localhost/vicidial/welcome.php`

## Notes importantes

- Le conteneur `vicidial` tourne en `privileged: true`, requis pour le
  timing DAHDI / Meetme d'Asterisk. Sans ça, audio et dialer instables.
- Plage RTP exposée : `10000-10500/udp`. À élargir si beaucoup d'appels.
- En production, préférer `network_mode: host` pour Asterisk (SIP/RTP)
  au lieu du mapping de ports, et garder MySQL au plus près du dialer
  (latence critique pour les scripts Perl).
