# SPDX-License-Identifier: BSD-3-Clause
#
# Gemeinsame Bausteine fuer die Pakete dieses Feeds. Jedes Paket bindet die
# Datei direkt nach gluon.mk ein:
#
#     include $(TOPDIR)/../package/gluon.mk
#     include ../neanderfunk.mk
#
# Kommentare aus Shell-Dateien: Gluon kuerzt beim Bau nur Lua unter luasrc/
# (luasrcdiet, CONFIG_GLUON_MINIFY). Alles unter files/ kaeme sonst samt
# Kommentaren ins Image. scripts/strip-shell-comments entfernt nach der
# Installation ganze Kommentar- und Leerzeilen aus allen Shell-Dateien des
# Pakets (Heredocs und mehrzeilige Strings bleiben unberuehrt, etc/config
# auch). Es ersetzt das fruehere gluonShellDiet.sh je Paket.
#
#   - Pakete ohne eigene Install-Regel: nichts weiter zu tun, die Vorgabe
#     unten installiert wie Gluon und kuerzt danach.
#   - Pakete mit eigener "define Package/<name>/install": als letzte Zeile
#     $(call NfStripShell,$(1)) anhaengen.

NF_FEED_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NF_STRIP_SHELL := $(NF_FEED_DIR)/scripts/strip-shell-comments

define NfStripShell
	sh $(NF_STRIP_SHELL) $(1)
endef

define NfInstall
	$(call Gluon/Build/Install,$(1))
	$(call NfStripShell,$(1))
endef

Package/$(PKG_NAME)/install ?= $(NfInstall)
