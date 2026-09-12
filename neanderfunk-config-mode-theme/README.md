neanderfunk-config-mode-theme
=============================

Ersetzt `gluon-config-mode-theme`: Layout (`view/theme/layout.html`) und
Stylesheet des Config-Mode. Das Theme ist responsiv bis Handybreite und hat
einen Dark Mode, der dem Browser folgt (`prefers-color-scheme`, kein eigener
Umschalter). Als Akzent dient Freifunk-Magenta `#D1005F`, Gelb `#FFB400`
markiert Fokus und Änderungen. Es gibt nur System-Schriften: Im Setup-Mode
hat der Client meist kein Internet, und Schriften kosten Flash.

Es gilt für jede Seite, die über das Layout läuft: Wizard, Erweiterte
Einstellungen, Information, Firmware-Upgrade und die Fehlerseiten 404/500.
Gestylt wird Gluons eigenes Markup (`gluon-web-model`-Templates, `admin/*`),
ohne dass eines davon geändert wird. Das Paket läuft auch allein, dann
bleibt es beim Wizard plus Erweiterten Einstellungen, nur modern gestylt. Die
Sammelseite kommt mit [neanderfunk-setup-mode](../neanderfunk-setup-mode/README.md).

Einbinden
---------

Beide Pakete liefern `view/theme/layout.html`. Deshalb muss Gluons Theme
raus, sonst bricht der Image-Bau am Dateikonflikt ab:

```lua
packages {
    '-gluon-config-mode-theme',
    'neanderfunk-config-mode-theme',
}
```

`PROVIDES:=gluon-config-mode-theme` erfüllt die Abhängigkeit von
`gluon-config-mode-core`. So macht es auch
`ffgraz-config-mode-theme-funkfeuer` in den community-packages.

Einzelheiten
------------

- **Menü:** Die Logik ist dieselbe wie bei Gluon. Oben stehen die sichtbaren
  Kategorien des Dispatcher-Baums, darunter die Seiten der aktuellen Kategorie
  als Reiter.
- **Cache:** CSS wird mit `?v=<Release>` geladen. `/static/` kommt ohne
  Cache-Control und mit festem Last-Modified. Ohne den Parameter behalten
  Browser nach einem Update das alte Stylesheet (vgl. `web-static-version.patch`
  im Firmware-Repo, der dasselbe für Gluons Theme macht).
- **Texte:** Sie laufen über `i18n/*.po` dieses Pakets. Das Layout holt sie
  ausdrücklich mit `i18n('neanderfunk-config-mode-theme')`, weil der
  Dispatcher das Layout unter dem Paketnamen `gluon-config-mode-theme`
  rendert.
- **CSS:** Ein File für beide Pakete. Teil 1 ist Gluons Markup, Teil 2 die
  Sammelseite.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).
