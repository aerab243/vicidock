# Vicidock — VICIdial all-in-one sur Docker

[![validate](https://github.com/aerab243/vicidock/actions/workflows/validate.yml/badge.svg)](https://github.com/aerab243/vicidock/actions/workflows/validate.yml)
[![docker-publish](https://github.com/aerab243/vicidock/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/aerab243/vicidock/actions/workflows/docker-publish.yml)
[![ghcr](https://img.shields.io/badge/ghcr.io-vicidock-blue?logo=docker)](https://github.com/aerab243/vicidock/pkgs/container/vicidock)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**Une seule image** avec tout VICIdial dedans (web, Asterisk, MariaDB,
daemons Perl), calquée sur **ViciBox 12.0.2**. **Versionnage semver
vicidock** : `v0.1.0`, `v0.1.1`, … (voir [versions](docs/versions.md)).

## Démarrage rapide

```bash
cp .env.example .env
# éditer .env : mots de passe + SERVER_IP (IP locale ou publique)
docker compose up -d
docker compose logs -f
```

Premier boot (~5-10 min) : MariaDB, schéma, données de base, `install.pl`,
crontab, IP et externip SIP/RTP configurés seuls. Ensuite :
`https://localhost/vicidial/welcome.php`, login `6666` + `ADMIN_PASSWORD`.

## Tags d'images

| Tag | Contenu |
|---|---|
| `latest` | Dernière release |
| `v0.1.1` | Release exacte (prod) |

Épingler en prod sur un tag exact (`VICIDOCK_TAG=v0.1.1`), jamais `latest`.
Sémantique : patch = correctifs, minor = nouveautés, major = ruptures
(détails + exemples : [versions](docs/versions.md)).

## Documentation

- [Installation](docs/installation.md) — prérequis, `.env`, ports, premier boot
- [Configuration](docs/configuration.md) — référence de toutes les variables
- [Versions](docs/versions.md) — politique de tags, mises à jour, releases
- [Opérations](docs/operations.md) — logs, supervision, backup, dépannage
- [Premier appel](docs/premier-appel.md) — carrier, campagne, agent (10 min)
- [Architecture](docs/architecture.md) — pourquoi une seule image, et comment
- [Dokploy](docs/dokploy.md) — déployer l'image publiée sur un PaaS

## Contenu de l'image

Base AlmaLinux 9 · VICIdial trunk SVN · Asterisk 18.21.0-vici (ConfBridge,
PJSIP, res_http_websocket, srtp) · Apache + PHP 8.2 · MariaDB 10.11 (interne
uniquement) · Perl + modules CPAN · crontab VICIdial · supervisord.
Détails : [architecture](docs/architecture.md).

## Licence

Vicidock (Dockerfile, scripts, compose, docs) : **Apache-2.0**, voir
[LICENSE](LICENSE). VICIdial embarqué dans l'image : sa licence propre
(AGPL, projet [vicidial.org](http://www.vicidial.org)).
