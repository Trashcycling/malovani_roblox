# Dokumentace Projektu

## Co to je?

Projekt je pixelová kreslicí aplikace postavená celá uvnitř Robloxu pomocí `Frame` instancí jako pixelů na `GuiObject` plátně. Podporuje čáry, polygony, obrysy tvarů (obdélníky a ovály), výplňový nástroj (kbelík), gumu a plnou historii vrácení změn — vše vykreslené přes 2D UI systém Robloxu bez jakýchkoli externích grafických knihoven.

## Jak spustit

1. Stáhněte si Roblox Studio z [https://create.roblox.com](https://create.roblox.com).
2. Otevřete stažený `.rbxl` soubor (File → Open from File).
3. Publikujte hru na Roblox (File → Publish to Roblox).
4. Následujte instrukce Robloxu pro spuštění a testování hry.

## Ovládání

| Vstup | Akce |
|---|---|
| **Levé tlačítko myši + tah** | Kreslení (čára / bod polygonu / tah tvaru) |
| **Pravé tlačítko myši + tah** | Začernění existujících pixelů (nástroj gumy) |
| **Shift** | Přichycení čar na násobky 45° / omezení tvarů na čtverec |
| **Ctrl** | Přepnutí na čárkovanou čáru u aktuálního tahu |
| **Mezerník** | Držením posouváte plátno |
| **L** | Vrátit poslední akci |
| **C** | Vymazat celé plátno a historii |
| **Delete / Backspace** | Smazat vybraný bod polygonu |
| **Dvojklik na bod** | Uzavřít aktivní polygon |
| **Tlačítko režimu** | Přepíná mezi Čára → Polygon → Tvary |
| **Tlačítko Eraser / Bucket** | Aktivuje nástroj (dalším kliknutím se vrátíte ke kreslení) |
| **Textové pole barvy** | Zadejte hodnotu barvy, např. `Color3.fromRGB(255, 0, 0)` |
