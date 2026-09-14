#!/bin/bash
# Exécute un daemon VICIdial après disponibilité de MariaDB.
# (supervisord démarre tout en parallèle : sans attente, les scripts Perl
# meurent en 255 sur le socket MySQL encore absent au boot.)
for _ in $(seq 1 60); do
  mysqladmin ping -h localhost --silent 2>/dev/null && break
  sleep 1
done
exec "$@"
