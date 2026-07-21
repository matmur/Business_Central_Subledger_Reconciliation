> 🇩🇪 Deutsch | [🇬🇧 English](README.en.md)

# Nebenbuch-Abstimmung für Business Central

![Business Central](https://img.shields.io/badge/Business%20Central-28.3-0078D4)
![AL Runtime](https://img.shields.io/badge/AL%20runtime-17.0-5C2D91)
![Localization](https://img.shields.io/badge/localization-DE-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

Eine kleine, fokussierte **Business-Central-(AL-)Erweiterung**, die **Abweichungen zwischen Nebenbuch und Hauptbuch** erkennt – wenn das Debitoren-Nebenbuch nicht mehr mit seinem Abstimmkonto im Hauptbuch übereinstimmt.

Für jedes **Debitoren-Abstimmkonto im Hauptbuch** vergleicht sie die **offenen Debitorenposten** (Summe des Restbetrags in Mandantenwährung) mit dem **Kontosaldo**. Jede Differenz ungleich null ist eine Abweichung – eine manuelle Sachkontobuchung, eine neu zugewiesene Buchungsgruppe, eine Teilstornierung. Reine Aggregation, keine Ermessensentscheidungen.

> **Demo:** _Hier folgt eine 2-minütige Aufzeichnung – eine Zeile wird nach einer manuellen Sachkontobuchung rot._

## Warum das wichtig ist

Nebenbuch und Hauptbuch sollen sich gemeinsam bewegen. Bucht man **direkt** auf ein Debitoren-Abstimmkonto oder weist eine Buchungsgruppe neu zu, laufen sie unbemerkt auseinander – meist erst zum Periodenabschluss entdeckt. Diese Erweiterung macht das jederzeit sichtbar – auf Knopfdruck oder nach Zeitplan.

## Die entscheidende Design-Entscheidung

**Abstimmung pro Abstimmkonto, nicht pro Buchungsgruppe.** Mehrere Buchungsgruppen können auf *dasselbe* Debitorenkonto verweisen (z. B. `EU` und `AUSLAND` → `1203`). Vergleicht man das Teil-Nebenbuch einer einzelnen Gruppe mit dem vollen Kontosaldo, entstehen Scheinabweichungen. Deshalb fasst die Logik das offene Nebenbuch aller Gruppen pro Konto zusammen und vergleicht **einmal pro Konto** – dort, wo die Zahlen tatsächlich vergleichbar sind.

## Objekte

| Objekt | ID | Funktion |
|---|---|---|
| enum `Recon Status` | 50100 | Ausgeglichen / Abweichung erkannt |
| table `Recon Finding` | 50101 | Ein Befund pro Konto und Lauf (`Delta`/`Status` werden in `OnInsert` abgeleitet) |
| codeunit `Sub-Ledger Recon Mgt.` | 50102 | Kern-Abstimmungslogik |
| codeunit `Recon Check Job` | 50103 | Wrapper für die Aufgabenwarteschlange (planbar) |
| page `Recon Findings` | 50104 | Listenoberfläche + Ausführen-Aktion + Rot/Grün-Formatierung |

## Technische Details

- **Nur als Erweiterung, upgrade-sicher.** Keine Basisobjekte werden verändert; es werden ausschließlich Basisdaten (`Customer Posting Group`, `Cust. Ledger Entry`, `G/L Account`) über deren öffentliche Schnittstelle *gelesen*.
- **FlowFields, korrekt behandelt.** `Remaining Amt. (LCY)` und der Hauptbuch-`Balance` sind FlowFields, keine gespeicherten Spalten – sie lassen sich daher nicht per `CalcSums` summieren. Die Logik nutzt `SetAutoCalcFields` (der Server berechnet sie während des Abrufs – eine mengenbasierte Abfrage, kein N+1) und `CalcFields` für den einzelnen Kontosaldo.
- **Daten verlassen den Mandanten nie.** Nur Befunde – keine externen Aufrufe.
- **Planbar.** Codeunit 50103 läuft als Aufgabenwarteschlangenposten; dieselbe Kernlogik bedient sowohl die Schaltfläche auf der Seite als auch den Zeitplaner.

## Ausführen

Benötigt VS Code + die **AL-Language**-Erweiterung (17.0) und eine BC-**28.3**-Sandbox.

1. Ordner in VS Code öffnen → **AL: Download symbols**.
2. `Ctrl+Shift+B` zum Kompilieren oder **F5** zum Veröffentlichen und Starten.
3. **Reconciliation Findings** öffnen → **Run Reconciliation Check**.

**Abweichung live sehen:** eine manuelle Fibu-Buchblattzeile direkt auf ein Debitoren-Abstimmkonto buchen, dann erneut ausführen – diese Zeile wird rot und zeigt ein Delta ungleich null.

Zum Einplanen: **Aufgabenwarteschlangenposten → Neu**, Codeunit `50103`, Wiederholung festlegen, Status = Bereit.

> `50100–50149` ist ein Entwicklungs-ID-Bereich; eine AppSource-Veröffentlichung erfordert einen bei Microsoft registrierten Bereich.

## Lizenz

[MIT](LICENSE) © 2026 Matthias Mur
