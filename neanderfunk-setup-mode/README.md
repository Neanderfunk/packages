neanderfunk-setup-mode
======================

Der Config-Mode auf **einer** Seite: oben der Wizard (Knoten, Standort,
Internetverbindung, Außenbereich), darunter jedes Formular der Erweiterten
Einstellungen als eingeklappte Gruppe mit Zustandszeile. Gespeichert wird mit
einem einzigen „Speichern & Neustarten“. Information und Firmware-Upgrade
bleiben eigene Seiten und stehen oben im Menü.

Heute verliert, wer vom Wizard in die Erweiterten Einstellungen wechselt,
seine Eingaben. Auf einer Seite gibt es keinen Wechsel mehr.

Braucht [neanderfunk-config-mode-theme](../neanderfunk-config-mode-theme/README.md)
(also `-gluon-config-mode-theme` in `image-customization.lua`):

```lua
packages {
    '-gluon-config-mode-theme',
    'neanderfunk-setup-mode',
}
```

Ohne das Paket ist der normale Wizard zurück.

Was die Seite tut und was nicht
-------------------------------

Die Formulare bleiben die von Gluon und den Paketen. Das Paket lädt, prüft
und schreibt sie so wie `gluon-web-model`. Es entscheidet nur, welche
Formulare auf die Seite kommen, wie sie aussehen und wann sie geschrieben
werden. Neue Seiten unter „Erweiterte Einstellungen“ (ein neues
`model()`-Paket) erscheinen ohne Zutun als weitere Gruppe.

Regeln beim Speichern (`luasrc/usr/lib/lua/neanderfunk/setup-mode.lua`):

1. **Alles oder nichts.** Geschrieben wird nur, wenn alle Formulare gültig
   sind. Passwort und Bestätigung vergleicht gluon-web-admin erst beim
   Schreiben, deshalb prüft das Paket das vorher. Bei einem Fehler öffnet sich
   der Abschnitt, das Feld ist markiert, die Seite springt hin.
2. **Nur geänderte Formulare.** Verglichen wird, was die Seite angezeigt hat,
   mit dem, was zurückkommt. Ein unverändertes Formular wird nicht geschrieben.
   Das spart Flash-Schreibvorgänge und vermeidet Nebenwirkungen. Das
   Passwortformular würde leer sonst `passwd -l root` ausführen, und
   `authorized_keys` würde neu geschrieben.
3. **Der Wizard zuletzt, und immer.** Sein Schreiben setzt `configured`, ruft
   `gluon-reconfigure` und startet neu.
4. **Commit wird zu Save, Reconfigure wird übersprungen**, solange die
   Erweiterten Formulare schreiben. Der `gluon-reconfigure` des Wizards
   committet alles auf einmal (`001-reset-uci` beginnt mit `uci commit`) und
   lässt alle Upgrade-Skripte laufen. Das ist nötig: Auf einer Seite haben
   alle Formulare ihren uci-Cursor vor dem ersten Schreiben geladen. Ein
   Formular, das ein Paket committet, das es nicht geändert hat, schriebe
   sonst eine veraltete Kopie zurück.

**Außenbereich** fragt Gluon doppelt ab: im Wizard (nur Outdoor-Geräte) und
unter WLAN. Auf der Seite steht es einmal. Die WLAN-Variante bleibt, weil
HT-Modus und der 5-GHz-Mesh-Schalter an ihr hängen. Auf Outdoor-Geräten
rückt sie in den Einrichtungsteil, auf allen anderen bleibt sie unter WLAN.

**Passwort:** Auf der Sammelseite bedeutet ein leeres Passwortfeld
„unverändert“. Zum Löschen gibt es den Schalter „Passwort entfernen“. Er
erscheint nur, solange ein Passwort gesetzt ist, und blendet die beiden
Felder aus. Gespeichert führt gluon-web-admin dann wie gewohnt
`passwd -l root` aus. Ist auch das Feld der SSH-Schlüssel leer, gibt es gar
keinen Fernzugriff mehr.

**Meldungen:** Unter einem Feld mit Fehler steht, was es erwartet, zum
Beispiel „Mindestens 12 Zeichen.“, „Keine gültige IPv4-Adresse.“ oder
„Pflichtfeld, bitte ausfüllen.“. Die Meldung ergibt sich aus dem Datentyp des
Feldes. Passwort und Bestätigung vergleicht die Seite schon im Browser
(„Die Passwörter sind nicht gleich.“) und noch einmal auf dem Knoten.

Die alten Adressen unter `admin/` funktionieren weiter und zeigen die
einzelnen Seiten wie bisher.

Interna, auf die sich das Paket verlässt
----------------------------------------

Bei jedem Gluon-Update prüfen, besonders beim Wechsel auf 2025.1:

- **Ladereihenfolge der Controller:** Der Dispatcher lädt
  `controller/*.lua`, dann `controller/*/*.lua`, jeweils nach `posix.glob`
  sortiert. `neanderfunk-setup-mode/` kommt nach `gluon-config-mode/` und
  überschreibt `{"wizard"}`. Ändert sich das, kommt der normale Wizard
  zurück. Kaputt geht dabei nichts.
- **Controller erneut ausgewertet:** Der Dispatcher-Baum hält nur Closures.
  Welche Einträge Formulare sind (`model()`) und zu welchem Paket sie
  gehören, liest das Paket deshalb aus einer zweiten Auswertung der
  Controller-Dateien mit eigener Umgebung.
- **Template je Knoten:** `node.template` und `node.package`. Nur Gluons
  Standard-Templates (`model/form`, `model/section`, `model/valuewrapper`)
  werden ersetzt. Eigene Templates der Pakete bleiben.
- **Wizard-Module:** `wizard.lua` lädt sie mit
  `setfenv(assert(loadfile(file)), getfenv())()(f, uci)`. Für die Zuordnung
  Modul → Gruppe wird `loadfile` für diesen einen Aufruf umhüllt. Lädt
  `wizard.lua` einmal anders, landen die Abschnitte in einer Gruppe ohne
  Titel.
- **Form-IDs** werden eindeutig gemacht (`id.nf-<seite>[-<form>]`), sonst
  hießen die Formulare aller Seiten `id.1`.

Test
----

In QEMU (x86-64, Setup-Mode, eine NIC mit hostfwd auf 192.168.1.1:80).
Templates, CSS, JS und Lua hängen nicht von der Architektur ab. Ins Overlay
kopiert, laufen sie auf jedem Knoten im Setup-Mode.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).
