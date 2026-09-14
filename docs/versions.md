# Versions et releases

## Convention : semver vicidock (`v0.1.0`)

Les tags versionnent **vicidock** (l'image + l'outillage), pas VICIdial :

- `v0.1.0`, `v0.1.1`, … (correctifs), `v0.2.0`, … (fonctionnalités).
- La rev VICIdial embarquée est fixée par le workflow
  (`VICIDIAL_SVN_REV`, défaut `3939`) et rappelée dans le label
  d'image `vicidock.vicidial-rev` + la matrice ci-dessous.
- Changer de rev SVN = au minimum MINOR (nouveau contenu dialer),
  matrice ci-dessous à jour.
- **Aucun tag n'est coupé sans validation explicite du mainteneur.**

## Sémantique : patch, minor, majeur (exemples)

- **PATCH** (`v0.1.0` → `v0.1.1`) : correctif rétrocompatible. Exemples :
  bug d'entrypoint (PID MariaDB, placeholders d'includes), bump de paquets,
  fix de sécurité Apache, docs.
- **MINOR** (`v0.1.x` → `v0.2.0`) : nouveauté rétrocompatible. Exemples :
  nouvelle variable optionnelle, nouveau programme supervisé, guides
  Dokploy/Openship, support WebRTC, montée de rev VICIdial.
- **MAJOR** (`v0.x` → `v1.0.0`) : rupture. Exemples : format du compose
  incompatible, variable obligatoire nouvelle, changement d'OS de base,
  passage multi-images, montée majeure d'Asterisk.
- Tant qu'on est en `v0.x`, l'API (compose, `.env`) peut encore bouger ;
  `v1.0.0` marquera la stabilité promise.

## Tags d'images publiés (GHCR)

| Tag | Sens | Usage |
|---|---|---|
| `latest` | Dernière release | Découverte, test |
| `v0.1.1` | Release exacte | **Prod** (un seul tag par release, jamais de tag mobile) |

Exemple : `ghcr.io/aerab243/vicidock:v0.1.0`. Tirage par digest
(`...@sha256:…`) toujours possible nativement, sans tag `sha-*` en vitrine.

## Mettre à jour

```bash
docker compose pull
docker compose down      # sans -v : la base est conservée
docker compose up -d
```

`down -v` (efface la base) uniquement pour repartir de zéro.

## Pipeline

- Push/PR sur `main` → workflow `validate` (< 3 min : shellcheck,
  compose config, lint Dockerfile, parse des confs, `php -l`). **Aucune
  publication.**
- Tag `v*` → `docker-publish` : build (~10 min, cache), **scan Trivy
  (bloque si CVE critique)**, push GHCR (tag exact + `latest`).
- `workflow_dispatch` (input `svn_rev`) → build + scan **sans push** :
  répétition générale avant de taguer.
- Pas de rebuild planifié : les patchs suivent via des tags à la demande.

## Couper une release

```bash
# 1. Valider d'abord sans publier : Actions → docker-publish → Run workflow
# 2. Taguer (après validation du mainteneur) :
git tag v0.1.1 && git push origin v0.1.1
# 3. Vérifier : run vert, tags présents sur GHCR, pull ciblé en local :
VICIDOCK_TAG=v0.1.1 docker compose pull
```

## Matrice actuelle

| Image | VICIdial | Asterisk | PHP | MariaDB | Base |
|---|---|---|---|---|---|
| `v0.1.1` | trunk rev 3939 (schéma 1729) | 18.21.0-vici | 8.2 (Remi) | 10.11 | AlmaLinux 9 |
