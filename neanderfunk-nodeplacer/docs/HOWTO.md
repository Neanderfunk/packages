# How-to: einen Knoten umziehen

Kurzanleitung für den eiligen Admin. Die vollständige Beschreibung des
Formats steht in [MANIFEST-FORMAT.md](MANIFEST-FORMAT.md), die Begründungen
in [DESIGN.md](DESIGN.md) und [DECISIONS.md](DECISIONS.md).

> **Multidomain-Firmware ist ungetestet.** Alles hier beschriebene bezieht
> sich auf Single-Domain-Firmware (Methode `firmware`). Die Methode `domain`
> existiert, ist aber noch nicht an Geräten erprobt (D-026).

## In drei Sätzen

Du legst eine signierte Textdatei `nodeplacer.manifest` auf euren
Firmware-Spiegel. Darin steht je Zeile, welcher Knoten wohin soll. Die Knoten
holen sie stündlich ab, und wer gemeint ist, zieht um.

**Was du brauchst:** die `node_id` des Knotens, die Spiegel-URL der
Zieldomain, und die Signaturschlüssel, die eure Knoten für
`nodeplacer.manifest` akzeptieren.

> **Lege die Steuerdatei auf einen Spiegel, der öffentlich erreichbar ist —
> mindestens über IPv4.** Dann erübrigt sich die ganze Bastelei mit ULA,
> Domain-Präfixen und wechselnden Adressen. Ein Name, der von überall
> auflöst, und ein Server, der von überall antwortet: Mehr braucht es nicht,
> und weniger führt zu Fehlern, die erst mitten im Umzug auffallen. Warum das
> mehr als Bequemlichkeit ist, steht unter
> [Communitywechsel](#communitywechsel-warum-eine-zwischenfirmware).

Die `node_id` ist die primäre MAC ohne Doppelpunkte. Am Knoten:

```sh
lua -e 'print(require"gluon.util".node_id())'
```

oder aus der Karte (`nodes.json`, Feld `nodeinfo.node_id`).

## Fall 1: Andere Domain, gleiche Community

Der Normalfall. Alles außer dem Spiegel bleibt gleich — Branch,
Signaturschlüssel und Schwelle sind dieselben, also stehen sie nicht in der
Zeile.

```
FORMAT=1
DATE=2026-09-17 08:00:00+00:00
EXPIRES=2026-10-01 08:00:00+00:00
COMMENT=MET-Rathaus zieht von 21_dias nach 02_met
9c9d7ec06b8d firmware mirror=http://firmware.ffnef.de/firmware/stable/02_met/sysupgrade target=nef-02_met
---
<Signaturen>
```

**`target=` immer angeben.** Es ist der `site_code`, den der Knoten nach dem
Umzug trägt. Ohne ihn kann der Knoten nicht unterscheiden, ob er noch
umziehen muss oder längst umgezogen ist und die Zeile nur noch dasteht — er
würde bei jedem Lauf erneut flashen (D-035).

Signieren, ablegen, fertig:

```sh
scripts/sign-test-manifest.sh mein.manifest      # Testschlüssel
python3 scripts/lint-nodeplacer-manifest.py mein.manifest.signed
# dann als nodeplacer.manifest auf den Spiegel legen
```

## Fall 2: Andere Community

Hier weichen mehr Dinge ab als der Spiegel. Gib nur an, was anders ist:

| Zieldomain weicht ab in | nötiger Key |
|---|---|
| nur Spiegel | keiner, nur `mirror=` |
| Branchname (`stable` heißt dort anders) | `branch=` |
| Signaturschlüsseln | `pubkey=` je Schlüssel |
| Zahl geforderter Signaturen | `good_signatures=` |

```
1459c0cf8d23 firmware mirror=http://fw.example.org/stable/sysupgrade branch=stable good_signatures=2 pubkey=<hex1> pubkey=<hex2> pubkey=<hex3>
```

**Bevor du das tust, lies den nächsten Abschnitt.** Ein Communitywechsel ist
kein größerer Domainwechsel, sondern eine andere Aufgabe — und er verlangt
laut D-020 ein zwischen beiden Communities abgestimmtes Verfahren. Knoten
"kalt" in eine fremde Domain zu schieben ist ausdrücklich off limits.

## Communitywechsel: warum eine Zwischenfirmware

**Das Problem:** Sysupgrade behält die UCI-Konfiguration. Nach dem Flash der
fremden Firmware stehen im Flash weiterhin die Einstellungen der **alten**
Community:

* Autoupdater-Branchnamen, Spiegel-URLs und Signaturschlüssel,
* Hostnamenpräfix und andere Werte aus der alten `site.conf`,
* Konfiguration von Paketen, die es in der Zielfirmware gar nicht gibt,
* Mesh-VPN-Einstellungen, die auf die alte Infrastruktur zeigen.

Die Zielfirmware schreibt beim Upgrade nur die Keys neu, für die sie selbst
ein Upgrade-Skript mitbringt. Alles andere bleibt stehen. Im schlimmsten Fall
landet der Knoten in der neuen Community, findet aber **keinen zu seinem
Branchnamen passenden Abschnitt** mehr — dann holt er keine Updates mehr ab
und ist aus der Ferne nicht mehr einzufangen.

**Die Lösung, die sich eingebürgert hat:** Die Zielcommunity baut eine
einmalige **Zwischenfirmware**. Deren einzige Aufgabe ist aufräumen:

1. Sie konvertiert oder löscht die UCI-Keys der alten Community.
2. Sie setzt ihre **eigenen** Autoupdater-URLs, Branchnamen und
   Signaturschlüssel.
3. Beim nächsten regulären Autoupdater-Lauf holt sich der Knoten damit
   **selbständig** die reguläre Firmware der Zielcommunity.

Der Nodeplacer zeigt also auf die **Zwischenfirmware**, nicht auf die
reguläre. Danach übernimmt der Autoupdater, und niemand muss den Knoten ein
zweites Mal anfassen.

Vorbilder für solche Migrationspakete gibt es: `ffac-change-autoupdater` und
`eulenfunk-migrate-updatebranch`.

> **Ungetestet.** Dieser Weg ist die Empfehlung aus D-020, nicht ein an
> Geräten erprobtes Verfahren. Wer ihn zuerst geht, sollte mit einem
> einzelnen Knoten anfangen, zu dem er physischen Zugang hat.

**Zwei Dinge, die dabei leicht übersehen werden:**

**Die Spiegel gehören auf eine öffentlich erreichbare Adresse, mindestens
über IPv4.** Das ist der eine Punkt, an dem ein Umzug unrettbar schiefgehen
kann.

Gemessen am 18.09.2026: Aus einer anderen Domain heraus ist die ULA-Adresse
der Ausgangsdomain **nicht** erreichbar (`Operation not permitted`), die
öffentliche Adresse dagegen schon. ULA-Präfixe sind an die Domain gebunden —
und genau die wechselt ja gerade. Auch die öffentliche IPv6 des Knotens ist
nach dem Umzug eine andere.

Steht in der Steuerdatei nur ein ULA-Spiegel, trägt er den Hinweg. Danach
erreicht der Knoten den Spiegel nicht mehr, auf dem die nächste Anweisung für
ihn läge — er kann sich **nicht selbst befreien**, und es hilft nur noch ein
Besuch vor Ort.

Ein Spiegel unter einem öffentlich auflösenden Namen mit **IPv4**-Adresse
erspart die gesamte Überlegung: Er ist vor, während und nach dem Umzug
derselbe, unabhängig von Domain, Präfix und davon, ob der Knoten am Zielort
überhaupt schon IPv6 hat. IPv6 zusätzlich anzubieten ist gut; sich **allein**
darauf zu verlassen, ist genau der Fallstrick.

> **Der Testlauf vom 18.09.2026 ist hier kein Vorbild.** Dort lag die
> Steuerdatei auf einem netzinternen Server, der nur über IPv6 erreichbar war
> — schlicht weil im Testbed kein Schreibzugriff auf einen Webserver mit
> öffentlicher IPv4 zur Verfügung stand. Deshalb musste beim Rückweg von Hand
> auf die öffentliche IPv6-Adresse umgestellt werden. Im Betrieb macht man
> das nicht nach, sondern legt die Datei gleich richtig ab.

**Der Rückweg ist ein zweiter vollständiger Durchgang.** Das Upgrade-Skript
`510-nodeplacer` schreibt Spiegel, Schlüssel und Schwelle bei **jedem**
Upgrade aus der `site.conf` neu. Nach dem Umzug gelten also die Werte der
Zieldomain. Wer zurück will, richtet alles noch einmal ein.

## Nach dem Umzug: was normal ist

Aus dem Testlauf vom 18.09.2026 (Mi 4A, `21_dias` → `48_rdvw` → zurück, beide
Richtungen über den regulären Cron):

| Beobachtung | Einordnung |
|---|---|
| Knoten antwortet auf seiner alten Adresse nicht mehr | **normal.** Die öffentliche IPv6 hängt an der Domain und wechselt mit ihr. Über die `node_id` in der Karte nachsehen, nicht die alte Adresse anpingen. |
| SSH meldet `Host key verification failed` | **normal**, neue Adresse. Der Hostkey selbst überlebt den Wechsel — Fingerabdruck gegen den alten Eintrag prüfen, dann eintragen. |
| Zwischen Cron-Lauf und erreichbarem Knoten vergehen ~3 Minuten | normal (Download, Flash, Neustart). |
| Bis zu einer Stunde passiert nichts | **normal.** Der Cron läuft stündlich zu einer **zufälligen** Minute, und die wird bei **jedem** Upgrade neu gewürfelt. Im Testlauf: 45 → 55 → 43. |
| Hostname, SSH-Keys, Mesh-VPN unverändert | so gewollt, Konfiguration bleibt erhalten. |

## Stolpersteine

**`DATE` darf nicht in der Zukunft liegen.** Der Knoten verwirft eine
Steuerdatei mit Zukunftsdatum, solange seine Uptime unter 600 s liegt
(`clock seems to be incorrect`). Bei Uhrenversatz zwischen Buildhost und
Knoten passiert das schneller als gedacht. **Datiere die Datei ein paar
Stunden zurück**, dann kann es nicht auftreten.

Ein *Wartefenster* gibt es dagegen nicht: Der Nodeplacer ruft den Autoupdater
mit `-f` auf und überspringt dessen Wahrscheinlichkeitsrechnung. Eine frisch
datierte Steuerdatei bleibt also nicht deswegen liegen.

**Ein neueres Datum gewinnt, ein älteres wird ignoriert.** Der Knoten merkt
sich das Datum der zuletzt angewandten Steuerdatei und nimmt nur Dateien mit
gleichem oder neuerem Datum an. Wer eine Korrektur nachschiebt, muss sie
**neuer** datieren als die fehlerhafte.

**Gegen Testbauten (`bro`) braucht es `good_signatures=1`.** Die
Signaturschwelle ist bewusst das **eigene** Vertrauensniveau des Knotens
(meist 3) und nicht das des Ziel-Branches — auch dann, wenn lokal ein
`autoupdater.broken` mit `good_signatures=1` konfiguriert ist (D-030/D-031).
Ein einmal signiertes Testimage wird sonst mit
`only carried 1 valid signatures, 3 are required` abgelehnt. Im
Produktivbetrieb zwischen zwei stable-Domains tritt das nicht auf.

**Ein HTTP 200 beweist nicht, dass die Datei da ist.** Manche Spiegel
beantworten jeden Pfad mit 200 und einer HTML-Seite. Prüfe den **Inhalt**:
ein Autoupdater-Manifest beginnt mit `BRANCH=`, eine Steuerdatei mit
`FORMAT=`.

```sh
curl -s "$URL" | head -3        # nicht: -o /dev/null -w '%{http_code}'
```

**Der Branchname muss zum Spiegel passen.** Ein `bro`-Bau liefert
`broken.manifest`, kein `stable.manifest`. Fehlt `branch=`, nimmt der Knoten
seinen eigenen Branch — und sucht dann die falsche Datei.

## Trocken testen

Der Nodeplacer lädt und prüft dabei alles, flasht aber nicht:

```sh
nodeplacer -n
```

Erwartete Ausgabe am Ende:
`Aborting successful upgrade because simulation was requested`, Exit 0. Ein
Trockenlauf verbucht **keinen** Versuch, du kannst ihn beliebig oft wiederholen.
