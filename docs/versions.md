# Versions et releases

## Convention

Un tag git = une release = une version de VICIdial :

- `v2.14-3939` → VICIdial 2.14, SVN rev 3939.
- Correctif d'infra sur la même rev : `v2.14-3939.1`, `.2`, …

Le workflow parse le tag tout seul (`VICIDIAL_SVN_REV` + numéro de build).

## Tags d'images publiés (GHCR)

| Tag | Sens | Usage |
|---|---|---|
| `latest` | Dernière release | Découverte, test |
| `2.14-3939` | Dernier build de cette rev | **Prod** (suit les patchs infra) |
| `2.14-3939.1` | Build exact | Reproductibilité stricte |
| `sha-…` | Commit source | Traçabilité |

Chaque image porte aussi les labels `vicidock.vicidial-rev` et
`vicidock.build` (`docker inspect`).

Épingler en prod dans le `.env` : `VICIDOCK_TAG=2.14-3939`.

## Mettre à jour

```bash
docker compose pull
docker compose down      # sans -v : la base est conservée
docker compose up -d
```

`down -v` (efface la base) uniquement pour repartir de zéro ou changer
de rev SVN.

## Pipeline

- Push/PR sur `main` → workflow `validate` (< 3 min : shellcheck,
  compose config, lint Dockerfile, parse des confs, `php -l`). **Aucune
  publication.**
- Tag `v*` → `docker-publish` : build (~10 min, cache), **scan Trivy
  (bloque si CVE critique)**, push GHCR.
- `workflow_dispatch` (input `svn_rev`) → build + scan **sans push** :
  répétition générale avant de taguer une nouvelle rev.
- Pas de rebuild planifié : les patchs de sécurité suivent via des tags
  patch à la demande.

## Couper une release

```bash
# 1. Valider d'abord sans publier : Actions → docker-publish → Run workflow
# 2. Taguer :
git tag v2.14-3939 && git push origin v2.14-3939
# 3. Vérifier : run vert, tags présents sur GHCR, pull ciblé en local :
VICIDOCK_TAG=2.14-3939 docker compose pull
```

## Matrice actuelle

| Image | VICIdial | Asterisk | PHP | MariaDB | Base |
|---|---|---|---|---|---|
| `2.14-3939` | trunk rev 3939 (schéma 1729) | 18.21.0-vici | 8.2 (Remi) | 10.11 | AlmaLinux 9 |
