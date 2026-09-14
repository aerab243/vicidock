#!/bin/bash
AC=/usr/share/astguiclient
mkdir -p /var/log/astguiclient
if [ -x "$AC/ADMIN_keepalive_ALL.pl" ]; then
  screen -dmS astguiclient perl "$AC/ADMIN_keepalive_ALL.pl"
else
  for p in AST_manager_listen.pl AST_manager_send.pl AST_VDauto_dial.pl AST_VDremote_agents.pl AST_VDadapt.pl AST_fastlog.pl; do
    [ -x "$AC/$p" ] && screen -dmS "${p%.pl}" perl "$AC/$p"
  done
fi
exec sleep infinity
