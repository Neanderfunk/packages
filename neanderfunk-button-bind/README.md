neanderfunk-button-bind
=======================

Mit diesem Paket kann im Config-Mode dem Wifi-Taster des Routers eine eigene
Funktion zugeordnet werden. Das Paket übernimmt dafür `/etc/rc.button/rfkill`
und legt OpenWrts eigenen Handler als `rfkill.owrt` daneben, der im Default-Fall
weiterhin aufgerufen wird.

Verfügbare Funktionen (`uci set button-bind.wifi.function=N; uci commit`):

| N | Funktion |
| --- | --- |
| 0 | Wifi an/aus (OpenWrt-Verhalten) |
| 1 | keine Funktion (Default) |
| 2 | Wifi-Reset |
| 3 | Nachtmodus: LEDs generell aus, nur während der Taster gedrückt ist an (braucht einen Reboot) |

Einstellbar ist das auch im Config-Mode unter „Taster".

Herkunft und Credits
--------------------

Portiert von **`ffffm-button-bind`** aus
<https://github.com/freifunk-ffm/packages/tree/master/ffffm-button-bind>,
© 2019 Freifunk Frankfurt am Main, MIT-Lizenz (siehe `LICENSE`). Die
Weiterentwicklung von rubo77 (Freifunk Nord) liegt unter
<https://github.com/rubo77/ffm-packages>.

Gegenüber dem Original geändert
-------------------------------

Nur das Nötige, damit es hier sauber läuft:

* Paketname auf `neanderfunk-*` gezogen, Upgrade-Skript entsprechend auf
  `888-neanderfunk-button-bind`.
* **Bugfix im Upgrade-Skript.** Das Original machte unbedingt
  `mv rfkill rfkill.owrt`. Das Skript läuft aber bei *jedem*
  `gluon-reconfigure` — also nicht nur beim Firmware-Upgrade, sondern auch beim
  Verlassen des Setup-Modes und beim Domain-Wechsel, ohne Sysupgrade
  dazwischen. Beim zweiten Lauf schiebt es damit den *eigenen Symlink* über das
  gesicherte Original: `rfkill.owrt` zeigt danach auf `rfkill.btnb`, und weil
  dessen Default-Zweig genau `rfkill.owrt` aufruft, führt ein Tastendruck in
  den Endlos-Aufruf. Auf einem Knoten nachgestellt und bestätigt. Gesichert
  wird jetzt genau einmal, und nur wenn `rfkill` wirklich noch die
  Originaldatei ist.
* `uci get` → `uci -q get` in beiden Skripten: fehlt die Config oder die
  Option, schrieb das Original eine Fehlermeldung nach stderr. Am Verhalten
  ändert sich nichts, der Default-Zweig greift so oder so.
* `CONFLICTS:=ffffm-button-bind`, weil beide dieselben Pfade und denselben
  rfkill-Handler beanspruchen.
* Der Aufruf `$(call GluonInstallI18N,$(PKG_NAME),$(1))` ist entfallen. Das
  Paket hat kein `i18n/`-Verzeichnis, und in Gluon v2023.2 nimmt
  `GluonInstallI18N` nur *ein* Argument (das Zielverzeichnis) — mit zwei
  Argumenten hätte es ein Verzeichnis namens `$(PKG_NAME)/lib/gluon/web/i18n`
  angelegt. Stattdessen `BuildPackageGluon`, das `files/`, `luasrc/` und ein
  eventuelles `i18n/` ohnehin selbst erledigt.

Die Oberflächentexte sind bewusst auf Deutsch geblieben, passend zum Rest
unserer Config-Mode-Seiten.
