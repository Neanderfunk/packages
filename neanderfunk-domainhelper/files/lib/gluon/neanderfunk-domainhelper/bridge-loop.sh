#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Schleife fuer "neanderfunk-domainhelper bridge" und "island", als
# procd-Instanz aus
# /etc/init.d/neanderfunk-domainhelper (respawn). Alle 91 s statt jede volle
# Minute aus micron.d: Die Laeufe fallen so nicht immer auf denselben
# Sekundenpunkt, und zwei Knoten an derselben Bruecke pruefen nicht im
# Gleichschritt.
#
# Der erste Lauf kommt bald nach dem Start: Ein Kabel, das eine Domain-Bruecke
# bildet, steckt nach jedem Neustart wieder.

INTERVAL=91

sleep 30
while : ; do
	/usr/sbin/neanderfunk-domainhelper bridge </dev/null >/dev/null 2>&1
	/usr/sbin/neanderfunk-domainhelper island </dev/null >/dev/null 2>&1
	sleep "$INTERVAL"
done
