# Dokumentace Projektu

## Co to je?
Tento projekt je pixelová kreslicí aplikace postavená celá uvnitř Robloxu pomocí `Frame` instancí jako pixelů na `GuiObject` plátně. Podporuje čáry, polygony, obrysy tvarů (obdélníky a ovály), výplňový nástroj (kbelík), gumu a plnou historii vrácení změn — vše vykreslené přes 2D UI systém Robloxu bez jakýchkoli externích grafických knihoven.

## Jak spustit

1. Stáhněte si Roblox Studio z [https://create.roblox.com](https://create.roblox.com).
2. Otevřete stažený `.rbxl` soubor (File → Open from File).
3. Publikujte hru na Roblox (File → Publish to Roblox).
4. Následujte instrukce Robloxu pro spuštění a testování hry.

## Ovládání

| Vstup | Akce |
|---|---|
| **Levé tlačítko myši + tah** | Kreslení (čára / bod polygonu / tah tvaru) |
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

## Jak to funguje

### Proč Frame instance jako pixely?

Roblox nenabízí LocalScriptům přímý přístup k pixelovému bufferu ani k API pro textury. Jediný způsob, jak na obrazovce vykreslit libovolné tvary, je přes UI instance. Každý „pixel" je `Frame` umístěný na správné pozici `(x, y)` na plátně.

### Vykreslování — slučování do úseků

Vytvářet jeden Frame na pixel by znamenalo desítky tisíc instancí, což by Roblox nezvládl. Místo toho se plátno vykresluje po řádcích. Pro každý řádek se sousedící pixely stejné barvy sloučí do jednoho širšího Framu — takzvaného úseku. Například 40 červených pixelů vedle sebe na jednom řádku se vykreslí jako jeden Frame o šířce 40, ne jako 40 samostatných Framů. Tím se počet instancí dramaticky sníží.

Po každé kreslicí operaci se přestaví jen ty řádky, které se změnily (tzv. „dirty rows"). Ostatní zůstanou nedotčené.

### Jak se kreslí objekty
Čáry se kreslí tak, že se projde cesta od začátku do konce krok po kroku, pixel po pixelu. Obdélníky jsou čtyři čáry. Ovály se aproximují jako mnohoúhelník s dostatečným počtem krátkých úseků, takže vypadají hladce.

### Výplň (flood fill)

Flood fill funguje jako „rozlévání barvy" — začne na pixelu, kam uživatel klikne, a šíří se do všech sousedních pixelů stejné barvy. Používá řádkový přístup: z výchozího bodu se rozšíří doleva a doprava na celý řádek, a pak totéž provede pro řádky nad a pod. Aby hra nezamrzla, zpracovává se nejvýše 2 500 pixelů za herní snímek a zbytek se dokončí v dalších snímcích. Pokud výplň dosáhne okraje plátna, považuje se oblast za neohraničenou a operace se zruší.

### Poolování Framů

Vytvářet a ničit `Frame` instance při každé změně by bylo nákladné. Místo toho se framy recyklují — když už nejsou potřeba, skryjí se a vrátí do poolu. Když je potřeba nový, nejdřív se zkontroluje pool, než se vytvoří nová instance.

### Vrstvení přes ZIndex

Každá kreslicí operace zvýší čítač `currentZIndex`. Tím je zajištěno, že novější tahy se vykreslí nad staršími, aniž by bylo potřeba cokoli přeřazovat. Aby hodnota nerostla donekonečna a vykreslené pixely nezačaly překrývat záhlaví aplikace, čítač má nastavenou horní hranici. Po jejím dosažení se všechny řádky přestaví na základní ZIndex.

### Systém vracení změn

Před každou kreslicí operací se celý pixelový stav naklonuje. Stisknutí L obnoví nejnovější uložený stav a přestaví všechny řádky. Historie je omezena na 20 záznamů.

## Omezení

Roblox engine není navržený pro vykreslování tisíců malých UI instancí jako pixelů. Při větším počtu nakreslených pixelů může dojít ke znatelnému zpomalení a vysokému zatížení CPU. Toto je základní omezení platformy, které nelze obejít v rámci LocalScriptu.
