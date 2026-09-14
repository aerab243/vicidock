# Premier appel en 10 minutes

Préreq : conteneur `healthy`, login `6666` sur
`https://<serveur>/vicidial/welcome.php`.

## 1. Changer le mot de passe admin

Sauf si `ADMIN_PASSWORD` était déjà positionné : Admin > Users > 6666.

## 2. Vérifier serveur et timezone

Admin > Servers > Modify Server : IP = `SERVER_IP`, timezone = `TZ`.
Voir [configuration](configuration.md).

## 3. Ajouter le trunk SIP (carrier)

Admin > Carriers > Add Carrier (coordonnées du provider VoIP).
Codec `ulaw` (G.711) des deux côtés pour commencer. Vérifier :

```bash
docker compose exec vicidock asterisk -rx "sip show registry"
```

## 4. Créer la campagne

Admin > Campaigns > Add Campaign :

- ID `TEST01`, nom explicite, dial `RATIO`, niveau `1.0`, active `Y`.
- Heures d'appel locales correctes.

## 5. Liste et leads

Admin > Lists > Add List (ID `10001`, rattachée à `TEST01`, active `Y`),
puis Load Leads (CSV : `phone_code`, `phone_number`, `first_name`,
`last_name`). Trois lignes suffisent pour tester.

## 6. Agent et poste

- Admin > Users > Add User : ID `100`, level `1`, groupe `AGENTS`.
- Admin > Phones > Add Phone : extension `100`, protocol `SIP`,
  login/pass SIP. Enregistrer un softphone (MicroSIP, Zoiper) dessus
  (en local : serveur `127.0.0.1`, port `SIP_PORT`).

## 7. Appeler

`https://<serveur>/agc/vicidial.php` → login agent → campagne `TEST01`
→ Resume. Audio dans les deux sens = dialer fonctionnel.
