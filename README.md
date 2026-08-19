> 🇩🇪 Deutsch | [🇬🇧 English](README.en.md)

# Nebenbuch-Abstimmung für Business Central

![Business Central](https://img.shields.io/badge/Business%20Central-28.3-0078D4)
![AL Runtime](https://img.shields.io/badge/AL%20runtime-17.0-5C2D91)
![Localization](https://img.shields.io/badge/localization-DE-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

Eine kleine, fokussierte **Business-Central-(AL-)Erweiterung**, die **Abweichungen zwischen Nebenbuch und Hauptbuch** erkennt – wenn das Debitoren-Nebenbuch nicht mehr mit seinem Abstimmkonto im Hauptbuch übereinstimmt.

Für jedes **Debitoren-Abstimmkonto im Hauptbuch** vergleicht sie die **offenen Debitorenposten** (Summe des Restbetrags in Mandantenwährung) mit dem **Kontosaldo**. Jede Differenz ungleich null ist eine Abweichung – eine manuelle Sachkontobuchung, eine Buchung ohne Debitor, eine Teilstornierung. Reine Aggregation, keine Ermessensentscheidungen.

## Demo

Ein Lauf gegen die BC-**28.3**-Sandbox (DE-Lokalisierung, CRONUS). Die Erweiterung ändert **nichts** an den Buchungen – sie liest die Daten live und macht eine Abweichung nur sichtbar.

**Ausgangslage – ausgeglichen.** Nebenbuch und Hauptbuch stimmen überein, `Delta` = 0,00:

![Reconciliation Findings, alle Zeilen grün, Delta 0,00, Status „Balanced"](docs/balanced.png)

**Nach einer Falschbuchung – Abweichung erkannt.** Es wird manuell direkt auf das Debitoren-Abstimmkonto `1202` (INLAND) gebucht. Nebenbuch und Hauptbuch laufen dadurch auseinander – der nächste Lauf deckt es auf, die Zeile wird rot, `Delta` = −500,00:

![Reconciliation Findings mit roter INLAND-Zeile, Delta −500,00, Status „Drift Detected"](docs/drift-detected.png)

`AUSLAND` und `EU` verweisen beide auf Konto `1203` und bleiben ausgeglichen – genau der Fall, den die Abstimmung pro Konto abdeckt (siehe unten).

## Warum das wichtig ist

Nebenbuch und Hauptbuch sollen sich gemeinsam bewegen. Bucht man **direkt** auf ein Debitoren-Abstimmkonto, ohne einen Debitor anzugeben, laufen sie unbemerkt auseinander – meist erst zum Periodenabschluss entdeckt. Diese Erweiterung macht das jederzeit sichtbar – auf Knopfdruck oder nach Zeitplan.

## Wie Abweichungen entstehen

| Ursache | Setzt „Direkt Buchen" voraus? |
|---|---|
| Manuelle Sachkontobuchung ohne Debitor (der Demo-Fall, weil am einfachsten reproduzierbar) | Ja |
| Datenmigration oder API-Integration schreibt direkt ins Hauptbuch, ohne Standard-Buchungsroutine | Nein |
| Teilstornierung, bei der nur eine Seite aufgelöst wurde | Nein |

Der Check prüft nicht, ob eine Regel verletzt wurde, sondern ob die Zahlen noch übereinstimmen – unabhängig von der Ursache.

Eine **nachträglich umgestellte Buchungsgruppe** ist *keine* solche Ursache, wird aber von Werkzeugen, die das Konto aus der aktuellen Einrichtung lesen, als eine gemeldet. Siehe die zweite Design-Entscheidung.

## Die zwei Design-Entscheidungen

**1. Abstimmung pro Abstimmkonto, nicht pro Buchungsgruppe.** Mehrere Buchungsgruppen können auf *dasselbe* Debitorenkonto verweisen (z. B. `EU` und `AUSLAND` → `1203`). Vergleicht man das Teil-Nebenbuch einer einzelnen Gruppe mit dem vollen Kontosaldo, entstehen Scheinabweichungen. Deshalb wird **einmal pro Konto** verglichen – dort, wo die Zahlen tatsächlich vergleichbar sind.

**2. Das Konto kommt aus der Buchung, nicht aus der Einrichtung.** Die Buchungsgruppe eines Postens steht beim Buchen fest; das Konto hinter dieser Gruppe kann später getauscht werden. Liest man das Konto aus der aktuellen Einrichtung, werden alte Posten gegen ein neues Konto gerechnet und **zwei** Konten melden eine Abweichung – das, welches die Posten verloren hat, und das, welches sie bekommen hat. Beide Zahlen sind richtig gerechnet, beide Meldungen sind falsch.

Stattdessen wird zu jedem offenen Posten der Sachposten derselben Buchung gesucht (gleiche Buchungsnummer, Herkunftsart Debitor, gleiche Debitorennummer) und dessen Konto verwendet. Der Standardbericht 33 „Debitoren und Kreditoren abstimmen" arbeitet aus der Einrichtung und zeigt das beschriebene Verhalten.

**Welche Konten geprüft werden**, kommt aus den Debitorensammelkonten der Buchungsgruppen. Wer zusätzlich die Unterkategorie *Forderungen* im Kontenplan pflegt, erweitert die Prüfung damit: Ein Konto, von dem eine Buchungsgruppe weggezogen wurde, bleibt erkennbar. Die Pflege ist optional – ohne sie verhält sich die Erweiterung, als gäbe es die zweite Quelle nicht. Siehe *Grenzen*.

## Grenzen

- **Keine Historie.** Jeder Lauf zeigt den Stand von heute und überschreibt den vorherigen. Ein Stichtag in der Vergangenheit würde erfordern zu rekonstruieren, welche Posten an jenem Tag offen waren.
- **Ein Konto, das weder in einer Buchungsgruppe steht noch als Forderungskonto klassifiziert ist, wird nicht geprüft** – auch wenn noch Posten darauf liegen. Da die Klassifizierung in vielen Mandanten gar nicht gepflegt ist, heißt das praktisch: entfernt man ein Konto vollständig aus der Einrichtung, verschwindet es aus der Prüfung. BC führt nirgends Buch darüber, dass ein Konto einmal ein Sammelkonto war, und innerhalb einer Buchung ist die Forderungszeile ohne diese Liste nicht von Erlös- und Steuerzeilen zu unterscheiden.
- **Aufwand je Posten.** Die Kontozuordnung kostet eine Abfrage pro offenem Posten. Für den Umfang dieser Erweiterung bewusst in Kauf genommen; bei sehr großen Offenposten-Beständen wäre die Zuordnung anders zu bauen.

## Objekte

| Objekt | ID | Funktion |
|---|---|---|
| enum `Recon Status` | 50100 | Ausgeglichen / Abweichung erkannt |
| table `Recon Finding` | 50101 | Ein Befund pro Konto und Lauf (`Delta`/`Status` werden in `OnInsert` abgeleitet) |
| codeunit `Sub-Ledger Recon Mgt.` | 50102 | Kern-Abstimmungslogik |
| codeunit `Recon Check Job` | 50103 | Wrapper für die Aufgabenwarteschlange (planbar) |
| page `Recon Findings` | 50104 | Listenoberfläche + Ausführen-Aktion + Rot/Grün-Formatierung |
| permissionset `Sub-Ledger Recon` | 50105 | Berechtigungen, damit Nutzer kein SUPER brauchen |
| codeunit `Recon Finding Tests` | 50149 | Tests für Differenz, Status und Kontozuordnung |

## Technische Details

- **Nur als Erweiterung, upgrade-sicher.** Keine Basisobjekte werden verändert; es werden ausschließlich Basisdaten (`Customer Posting Group`, `Cust. Ledger Entry`, `G/L Entry`, `G/L Account`, `G/L Account Category`) über deren öffentliche Schnittstelle *gelesen*.
- **FlowFields, korrekt behandelt.** `Remaining Amt. (LCY)` und der Hauptbuch-`Balance` sind FlowFields, keine gespeicherten Spalten – sie lassen sich daher nicht per `CalcSums` summieren. Für die Menge der Posten berechnet der Server sie während des Abrufs mit (`SetAutoCalcFields`), für den einzelnen Kontosaldo wird `CalcFields` verwendet.
- **Kosten transparent.** Das Lesen der Restbeträge bleibt mengenbasiert; die Kontozuordnung dagegen ist eine Abfrage je offenem Posten. Siehe *Grenzen*.
- **Ableitung in der Tabelle.** `Delta` und `Status` entstehen im `OnInsert` der Befundtabelle, nicht im Aufrufer – jede Zeile ist damit in dem Moment stimmig, in dem sie geschrieben wird, unabhängig davon, wer sie schreibt.
- **Vollständig deutsch beschriftet.** Alle 24 Beschriftungen und Tooltips sind in `Translations/Sub-Ledger Reconciliation.de-DE.xlf` übersetzt (`features: ["TranslationFile"]`) – in der Oberfläche steht kein englischer Feldname.
- **Daten verlassen den Mandanten nie.** Nur Befunde – keine externen Aufrufe.
- **Planbar.** Codeunit 50103 läuft als Aufgabenwarteschlangenposten; dieselbe Kernlogik bedient sowohl die Schaltfläche auf der Seite als auch den Zeitplaner.

## Ausführen

Benötigt VS Code + die **AL-Language**-Erweiterung (17.0) und eine BC-**28.3**-Sandbox.

1. Ordner in VS Code öffnen → **AL: Download symbols**.
2. `Ctrl+Shift+B` zum Kompilieren oder **F5** zum Veröffentlichen und Starten.
3. **Abstimmung Debitoren** öffnen → **Abstimmung starten**.

**Abweichung live sehen:** eine manuelle Fibu-Buchblattzeile direkt auf ein Debitoren-Abstimmkonto buchen, dann erneut ausführen – diese Zeile wird rot und zeigt ein Delta ungleich null.

Zum Einplanen: **Aufgabenwarteschlangenposten → Neu**, Codeunit `50103`, Wiederholung festlegen, Status = Bereit.

> `50100–50149` ist ein Entwicklungs-ID-Bereich; eine AppSource-Veröffentlichung erfordert einen bei Microsoft registrierten Bereich.

## Kontakt

**Matthias Mur** — .NET/SQL-Entwickler mit Hintergrund in produktiven ERP-Systemen (kundenspezifische .NET-Erweiterungen, Abrechnungs- und Service-Management-Logik, SQL-Validierung, Debugging im Live-Betrieb), jetzt Business Central (AL). Verfügbar für freiberufliche BC- und ERP-Projekte, 100 % remote im DACH-Raum.

[LinkedIn](https://www.linkedin.com/in/matthias-mur/) · [matthias@mur-consulting.com](mailto:matthias@mur-consulting.com)

## Lizenz

[MIT](LICENSE) © 2026 Matthias Mur
