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
80afcacfc55d firmware branch=stable mirror=http://firmware.ffnef.de/firmware/stable/21_dias/sysupgrade mirror=http://[fd66:666e:6566:6415::733]/firmware/stable/21_dias/sysupgrade target=nef-21_dias
80afcacfc55e firmware mirror=http://firmware.ffnef.de/firmware/stable/21_dias/sysupgrade target=nef-21_dias
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
<node_id> firmware mirror=<url> [mirror=<url> ...] [branch=<name>]
                   [pubkey=<hex> ...] [good_signatures=<n>] [target=<site_code>]
```

| Key | Pflicht | Wiederholbar | Bedeutung |
|---|---|---|---|
| `mirror` | ja | ja | Autoupdater-Mirror der Zieldomain (Basis-URL, unter der `<branch>.manifest` und die Images liegen). Reihenfolge = Reihenfolge, in der der Autoupdater sie probiert (er mischt Kommandozeilen-Mirrors nicht). |
| `branch` | nein | nein | Autoupdater-Branch auf dem Zielserver. Fehlt er, gilt der aktuelle `autoupdater.settings.branch` des Knotens. |
| `pubkey` | nein | ja | Signaturschluessel, mit denen das Firmware-Manifest der Zieldomain geprueft wird. Fehlt der Key, gelten die Schluessel des Knotens. |
| `good_signatures` | nein | nein | Wie viele gueltige Signaturen das Firmware-Manifest der Zieldomain tragen muss. Fehlt der Key, gilt das eigene aktuelle Vertrauensniveau des Knotens (D-032) - derselbe Wert, mit dem `nodeplacer.manifest` selbst schon geprueft wurde -, **nicht** ein zufaellig lokal unter dem Zielbranch-Namen konfigurierter Wert. |
| `target` | **nein, aber dringend empfohlen** | nein | Der `site_code`, den der Knoten nach dem Umzug tragen sollte (z. B. `nef-02_met`). Ist er angegeben, prueft der Knoten ihn **vor** jeder Aktion gegen seinen eigenen aktuellen `site_code`; stimmen sie ueberein, ist nichts zu tun - derselbe Kurzschluss wie bei der Methode `domain` (siehe D-035). |

### Branch, Schluessel und Schwelle sind unabhaengig

Die drei Angaben beschreiben drei Eigenschaften der Zieldomain, die
einzeln gleich oder anders sein koennen. Der Normalfall innerhalb einer
Community ist, dass alle drei gleich bleiben; dann steht nur `mirror` in
der Zeile.

| Zieldomain weicht ab in | noetiger Key |
|---|---|
| nichts (gleiche Community) | keiner, nur `mirror` |
| Branchname | `branch=` |
| Signaturschluesseln | `pubkey=` (so oft wie noetig) |
| Mindestzahl Signaturen | `good_signatures=` |

Beispiel fuer eine fremde Community, die ihre Firmware mit zwei von drei
eigenen Schluesseln freigibt, waehrend der Knoten selbst drei fordert:

```
bc241158f1c6 firmware mirror=http://fw.example.org/stable/sysupgrade good_signatures=2 pubkey=<hex1> pubkey=<hex2> pubkey=<hex3>
```

`target=` fehlt hier bewusst: bei einer fremden Community ist der genaue
`site_code` der Zieldomain oft nicht bekannt (D-020, D-035). Ist er
bekannt, gehoert er auch hierher, aus demselben Grund wie im
Normalfall unten.

Was der Knoten damit macht:

* Er schreibt die Werte **nur ins UCI-Delta** (`/tmp/.uci`) der
  Autoupdater-Branch-Section, ruft den Autoupdater auf und vergisst alles
  beim Reboot. Die Konfiguration im Flash bleibt unangetastet.
* Angegeben wird nur, was abweicht. Was fehlt, bleibt auf dem Wert des
  Knotens; das gilt auch, wenn der Branch lokal schon existiert.
* Existiert der Branch lokal nicht, sind `pubkey`-Angaben Pflicht. Fehlt
  dann `good_signatures`, gilt die strengste Auslegung: alle uebergebenen
  Schluessel muessen unterschrieben haben.
* Eine Schwelle groesser als die Zahl der wirksamen Schluessel ist ein
  Fehler. Die Zeile wird verworfen, sonst bricht der Lauf ab.

**Vertrauensanker:** Wer Schluessel und Schwelle setzen darf, kann einen
Knoten auf nahezu beliebige Firmware zeigen lassen. Der einzige Anker ist
damit die Signatur unter `nodeplacer.manifest` selbst (D-030).

### Warum `target` bei `firmware` dringend empfohlen ist (D-035)

`--force-version` (siehe DESIGN.md 3.2) uebergeht den Versionsvergleich
absichtlich, weil Ziel- und Ausgangsfirmware bei einem Umzug meist die
gleiche Releasenummer tragen. Dadurch kann der Knoten allein aus Branch
und Mirror-URL **nicht** unterscheiden, ob er noch wechseln muss oder den
Wechsel schon vollzogen hat und die Zeile in der Steuerdatei nur noch nicht
entfernt wurde. Ohne `target` wiederholt er den Vorgang deshalb, begrenzt
nur durch den Versuchszaehler (D-012, drei Versuche pro sieben Tage,
rollend) - kein unendlicher Loop, aber auch kein sauberes "nichts zu tun".

`target` macht dieses "schon da" explizit und beendet den Lauf, bevor
irgendetwas an UCI oder dem Autoupdater angefasst wird. Es bleibt
**optional**, weil bei einem Umzug in eine fremde Community (D-020) der
genaue `site_code` der Zieldomain nicht immer bekannt ist; in dem Fall
greift weiterhin nur der Versuchszaehler als Bremse.

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
* Schluessel und Mindestzahl kommen aus dem **aktiven
  Autoupdater-Branch** des Knotens, also aus
  `autoupdater.<settings.branch>.pubkey` und `.good_signatures` (D-031).
  Wer eine Firmware fuer den Knoten freigeben darf, darf ihn auch
  verschieben. Auf einem Knoten im Branch `stable` mit drei geforderten
  Signaturen braucht die Steuerdatei also drei.
* `nodeplacer.pubkeys` und `nodeplacer.good_signatures` in site.conf
  ueberschreiben das, sind aber selten sinnvoll.

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
2. Pruefen, **bevor** signiert wird:
   `scripts/lint-nodeplacer-manifest.py nodeplacer.manifest`
   (D-036; Exit-Code 0 = in Ordnung, 1 = Fehler gefunden, nicht signieren).
3. Signieren, so oft wie noetig, mit dem Firmware-Werkzeug:
   `gluon/contrib/sign.sh <secret> nodeplacer.manifest`
   (jeder Maintainer einmal; haengt je eine Signaturzeile an).
4. Auf alle Mirrors legen.
5. Eintraege entfernen, sobald der Knoten in der Zieldomain angekommen ist;
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
