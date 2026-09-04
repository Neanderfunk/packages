# Manifest-Format (Entwurf, FORMAT=1)

Die Steuerdatei folgt dem Aufbau des Autoupdater-Manifests: Kopfzeilen als
`KEY=VALUE`, dann Nutzdatenzeilen, dann eine Zeile `---`, dann Signaturen.
Alles vor `---` wird zeilenweise (jede Zeile plus `\n`) in SHA256 gehasht;
das ist exakt der Bereich, den `gluon/contrib/sign.sh` signiert.

## Beispiel

```
FORMAT=1
DATE=2026-09-04 12:00:00+02:00
EXPIRES=2026-10-04 12:00:00+02:00
COMMENT=Umzug Wuelfrath-Nord nach Diaspora, Ticket 123
80afcacfc55c domain target=ffnef21dias
80afcacfc55d firmware branch=stable mirror=http://firmware.ffnef.de/firmware/stable/21_dias/sysupgrade mirror=http://[fd66:666e:6566:6415::733]/firmware/stable/21_dias/sysupgrade
80afcacfc55e firmware mirror=http://firmware.ffnef.de/firmware/stable/21_dias/sysupgrade
---
2f0c...signatur1...
9a44...signatur2...
```

## Kopfzeilen

| Key | Pflicht | Bedeutung |
|---|---|---|
| `FORMAT` | ja | Formatversion, aktuell `1`. Unbekannte Versionen: Abbruch. |
| `DATE` | ja | Erstellungszeit, RFC-3339-artig wie im Autoupdater (`YYYY-MM-DD HH:MM:SS+HH:MM`). Der Knoten wendet kein Manifest an, dessen `DATE` aelter ist als das zuletzt angewandte. |
| `EXPIRES` | ja | Ablaufzeit, gleiches Format. Danach wird das Manifest ignoriert. Begrenzt Replay. |
| `COMMENT` | nein | Freitext fuer Menschen; wird vom Knoten ignoriert, aber mitsigniert. |
| `WINDOW` | nein, reserviert | Zeitfenster `HH-HH` (Ortszeit des Knotens), in dem Aktionen ausgefuehrt werden. In FORMAT=1 noch nicht ausgewertet. |

Unbekannte Kopfzeilen (`^[A-Z_]+=`) werden ignoriert, damit spaetere
Formatversionen abwaertskompatibel Felder ergaenzen koennen, solange
`FORMAT` gleich bleibt.

## Nutzdatenzeilen

```
<node_id> <methode> <key>=<wert> [<key>=<wert> ...]
```

Whitespace-getrennte Token. Die ersten beiden sind positional: Node-ID
(12 Hex-Zeichen, Primary-MAC ohne Doppelpunkte, wie `gluon.util.node_id()`)
und Methode. Alle weiteren Token sind `key=wert`, in beliebiger Reihenfolge.
Ein Key darf wiederholt werden und bildet dann eine Liste in
Reihenfolge des Auftretens (`mirror=... mirror=...`). Werte enthalten kein
Whitespace (URLs mit Leerzeichen sind ohnehin nicht zulaessig, Prozent-
Kodierung ist erlaubt). Ein unbekannter Key, ein Token ohne `=` oder ein
fehlender Pflicht-Key macht die **ganze Zeile ungueltig**; der Knoten
loggt das und tut nichts. Diese Strenge ist Absicht: bei Handpflege soll ein
Tippfehler zu "nichts passiert" fuehren, nicht zu "etwas anderes passiert".

### Methode `domain`

```
<node_id> domain target=<domain_code>
```

| Key | Pflicht | Bedeutung |
|---|---|---|
| `target` | ja | Domain-Code oder Alias; muss als `/lib/gluon/domains/<code>.json` in der Firmware existieren. |

Nur bei Multidomain-Firmware ausfuehrbar.

### Methode `firmware`

```
<node_id> firmware mirror=<url> [mirror=<url> ...] [branch=<name>] [pubkey=<hex> ...]
```

| Key | Pflicht | Wiederholbar | Bedeutung |
|---|---|---|---|
| `mirror` | ja | ja | Autoupdater-Mirror der Zieldomain (Basis-URL, unter der `<branch>.manifest` und die Images liegen). Reihenfolge = Reihenfolge, in der der Autoupdater sie probiert (er mischt Kommandozeilen-Mirrors nicht). |
| `branch` | nein | nein | Autoupdater-Branch auf dem Zielserver. Fehlt er, gilt der aktuelle `autoupdater.settings.branch` des Knotens. |
| `pubkey` | nein | ja | Nur noetig, wenn `branch` lokal nicht konfiguriert ist. Wird nur im UCI-Delta fuer diesen einen Autoupdater-Lauf gesetzt. |

### Warum `key=wert` statt Positionsfeldern oder Kommalisten (D-018)

* Eine Mirror-Liste in einer Zeile braucht ein Listenformat. Optionen:
  positional (`... stable URL URL URL`), kommagetrennt
  (`mirrors=URL,URL,URL`) oder wiederholter Key (`mirror=URL mirror=URL`).
* Wiederholter Key gewinnt: bleibt lesbar (ein Mirror pro Token), kein
  Trennzeichen, das in URLs vorkommen koennte (Komma ist in URLs erlaubt),
  Reihenfolge der Keys egal, spaeter erweiterbar (neue Keys), und
  Tippfehler sind erkennbar (unbekannter Key -> Zeile ungueltig).
* Positionsfelder scheitern, sobald ein optionales Feld (branch) vor der
  Liste steht und der Ersteller es weglaesst.

### Zeilenlaenge

Vier Neanderfunk-Mirrors zu je etwa 95 Zeichen plus Node-ID und Keys ergeben
etwa 450 Zeichen. Das Zeilenlimit des Autoupdater-Parsers (512) wird im
C-Helfer auf 2048 angehoben. Eine Zeile pro Knoten bleibt Pflicht; die
Zeile mit derselben Node-ID zu wiederholen ist kein Fortsetzungsmechanismus
(erste Zeile gewinnt).

## Zeilen, die der Knoten ignoriert

* Leerzeilen und Zeilen, die mit `#` beginnen (Kommentare; werden trotzdem
  mitgehasht, sind also signiert).
* Nutzdatenzeilen fuer andere Node-IDs.
* Nach dem ersten Treffer fuer die eigene Node-ID wird nicht weitergesucht;
  doppelte Eintraege sind ein Fehler des Erstellers, der erste gewinnt.

## Signaturen

* Nach `---` je Zeile eine Hex-Signatur, erzeugt mit `ecdsasign` ueber den
  Teil vor `---` (genau wie `contrib/sign.sh` es tut).
* Gueltig, wenn mindestens `good_signatures` (aus site.conf) Paare
  (Pubkey, Signatur) passen.
* Pubkeys: `nodeplacer.pubkeys` aus site.conf, sonst die Pubkeys des
  aktuell konfigurierten Autoupdater-Branches.

## Dateiname auf dem Server

```
<mirror>/nodeplacer.manifest
```

Genau eine Datei pro Mirror fuer die ganze Community, bei Neanderfunk also
eine zentrale Datei fuer alle 40+ Domains (D-010). Alle Knoten schauen in
dieselbe Datei. 404 heisst "nichts zu tun" und ist der Normalfall.

## Pflege von Hand (D-017)

1. Datei editieren: Kopfzeilen anpassen (`DATE` auf jetzt, `EXPIRES` auf
   z. B. vier Wochen spaeter), Knotenzeilen ergaenzen oder entfernen, alte
   Signaturen unter `---` loeschen.
2. Signieren, so oft wie noetig, mit dem Firmware-Werkzeug:
   `gluon/contrib/sign.sh <secret> nodeplacer.manifest`
   (jeder Maintainer einmal; haengt je eine Signaturzeile an).
3. Auf alle Mirrors legen.
4. Eintraege entfernen, sobald der Knoten in der Zieldomain angekommen ist;
   spaetestens `EXPIRES` raeumt auf.

Jede Aenderung am Teil vor `---` macht alle bestehenden Signaturen
ungueltig; das ist gewollt.

## Groessenbetrachtung

Die Datei enthaelt nur Ausnahmefaelle und wird nach dem Umzug von Hand
bereinigt. Annahme (D-021): nie mehr als 100 Zeilen, in der Regel unter
10. Eine Zeile ist 30 bis 500 Bytes, die Datei also hoechstens etwa 50 KB.
Sie wird komplett im RAM gehalten. Der C-Helfer begrenzt den Download hart
(Vorschlag 256 KB) und das Zeilenlimit auf 2048 Zeichen.

## Warum nicht JSON?

* `sign.sh` und `ecdsasign` arbeiten zeilenbasiert; JSON muesste
  kanonisiert werden, sonst bricht die Signatur bei Neuformatierung.
* Maintainer kennen das Autoupdater-Manifest; das neue Format sieht
  vertraut aus und laesst sich mit `cat`, `grep` und `sign.sh` bearbeiten.
* Parser in Lua ist trivial (`line:match`), kein jsonc-Umweg.
