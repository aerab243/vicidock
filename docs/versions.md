# Versions et releases

## Convention : semver vicidock (`v0.1.0`)

Les tags versionnent **vicidock** (l'image + l'outillage), pas VICIdial :

- `v0.1.0`, `v0.1.1`, … (correctifs), `v0.2.0`, … (fonctionnalités).
- La rev VICIdial embarquée est fixée par le workflow
  (`VICIDIAL_SVN_REV`, défaut `3939`) et rappelée dans le label
  d'image `vicidock.vicidial-rev` + la matrice ci-dessous.
- Changer de rev SVN = nouveau tag mineur/patch + matrice à jour.

## Tags d'images publiés (GHCR)

| Tag | Sens | Usage |
|---|---|---|
| `latest` | Dernière release | Découverte, test |
| `0.1` | Dernière `0.1.x` | **Prod** (suit les patchs) |
| `0.1.0` | Build exact | Reproductibilité stricte |
| `sha-…` | Commit source | Traçabilité |

Épingler en prod dans le `.env` : `VICIDOCK_TAG=0.1`.

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
  (bloque si CVE critique)**, push GHCR.
- `workflow_dispatch` (input `svn_rev`) → build + scan **sans push** :
  répétition générale avant de taguer.
- Pas de rebuild planifié : les patchs suivent via des tags à la demande.

## Couper une release

```bash
# 1. Valider d'abord sans publier : Actions → docker-publish → Run workflow
# 2. Taguer :
git tag v0.1.0 && git push origin v0.1.0
# 3. Vérifier : run vert, tags présents sur GHCR, pull ciblé en local :
VICIDOCK_TAG=0.1.0 docker compose pull
```

## Matrice actuelle

| Image | VICIdial | Asterisk | PHP | MariaDB | Base |
|---|---|---|---|---|---|
| `0.1.0` | trunk rev 3939 (schéma 1729) | 18.21.0-vici | 8.2 (Remi) | 10.11 | AlmaLinux 9 |
