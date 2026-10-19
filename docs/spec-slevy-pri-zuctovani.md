# Funkční specifikace – úprava cen při zúčtování akce

Verze 2, 19. 10. 2026. Změna oproti verzi 1: **zdražení se chová stejně jako zlevnění**, jen opačným směrem.

---

## 1. Co se má stát

Dnes zúčtování akce jen projede nevyúčtované lidi a strhne jim z konta, co jim vyšlo podle cen zadaných u akce. Nově bude zúčtování **poslední místo, kde se dají ceny doladit**: vyšlo to jinak, než se čekalo, a rozdíl se má promítnout všem.

Při zúčtování tedy admin uvidí ceník akce (ubytování, zvýhodněné ubytování a všech šest položek) a bude ho moct přepsat. Z rozdílu se spočítá, komu co přibude nebo ubude.

---

## 2. Kdo dostane opravu a komu se jen strhne jiná částka

Při zúčtování jsou účastníci ve dvou skupinách:

| Skupina | Co se s nimi stane |
|---|---|
| **Ještě nevyúčtovaní** | Strhne se jim rovnou **nová cena**, ať je nižší nebo vyšší. Žádná oprava navíc – není co opravovat. |
| **Vyúčtovali se sami** | Už mají strženo podle **starých** cen. Spočítá se rozdíl a o ten se jim **konto zvýší nebo sníží** samostatným pohybem. |

**Zlevnění** – ubytování 150 → 120 Kč:

- Jana se nevyúčtovala. Měla 3 noci: místo 450 Kč jí strhneme 360 Kč.
- Petr se vyúčtoval sám a má strženo 650 Kč. Při nových cenách by to bylo 560 Kč → **+90 Kč na konto**.

**Zdražení** – ubytování 150 → 180 Kč:

- Janě se strhne rovnou 540 Kč místo 450 Kč.
- Petrovi by nově vyšlo 740 Kč místo 650 → **−90 Kč z konta**.

Výsledek je, že jsou na tom oba stejně, ať se vyúčtovali sami nebo ne. To je na tom to dobré: nikdo nemá důvod čekat s vyúčtováním na to, jak admin nakonec ceny nastaví.

Dvě pojistky, aby zdražení nikoho nepřekvapilo:

- Ve formuláři zúčtování je dopředu vidět, **komu se kolik strhne**, jmenovitě – ne jen souhrn.
- Kdo se doúčtováním dostane do dluhu pod limit, je ve výpisu **označený**, ať admin ví, s kým se domluvit.

---

## 3. Jak to bude vypadat pro admina

Tlačítko **💰 Zúčtovat** v detailu akce místo dnešního `confirm()` otevře formulář:

```
💰 Zúčtovat akci
Jesenní Ostrov · 12 přihlášených

CENÍK – uprav, pokud to vyšlo jinak
  🏠 Ubytování            [ 120 ] Kč/noc     (původně 150)
  🧒 Ubytování zvýhodněné [  80 ] Kč/noc
  Pivo                    [  35 ] Kč/ks
  Limonáda                [  25 ] Kč/ks
  …                                     (jen vyplněné položky)

CO TO UDĚLÁ
  7 lidem se strhne z konta       −4 830 Kč
  5 lidem se konto opraví           +620 Kč
  ↳ Petr Platic +90, Jana Nová +150, Tomáš −40 ⚠ dluh

[ Zrušit ]            [ Zúčtovat akci ]
```

Čísla se přepočítávají při každé změně ceny, takže admin vidí dopad dřív, než na cokoli klikne. Potvrzení (`Opravdu zúčtovat?`) zůstává.

Když admin ceny nezmění, chová se to **přesně jako dnes** – žádné opravy, jen stržení.

---

## 4. Co se zapíše

Nové ceny se **uloží k akci**. Od té chvíle je akce zúčtovaná a ceník v ní odpovídá tomu, co se doopravdy účtovalo – přehled vyúčtování pak sedí a nehlásí rozdíly.

Pohyby na kontě:

- **nevyúčtovaní** → jedna transakce `event_charge` (mínus), jako dnes, v popisu nové ceny,
- **vyúčtovaní sami** → jedna transakce `event_adjustment` s **kladnou nebo zápornou** částkou podle toho, kterým směrem se cena hnula. Popis: „Oprava ceny akce: Jesenní Ostrov (ubytování 150 → 120 Kč)",
- u člověka, co se vyúčtoval sám, se zároveň **opraví částka jeho vyúčtování** na novou, aby přehled seděl. Oba pohyby v historii zůstávají, takže je dohledatelné, co se stalo.

Rozdíl 0 Kč žádnou transakci nevyrobí.

**Celé zúčtování poběží jako jedna operace v databázi.** Dnes to prohlížeč projíždí člověka po člověku – když se zavře notebook uprostřed, půlka lidí má strženo a půlka ne, a akce není uzavřená. Nově buď proběhne všechno, nebo nic. To je mimochodem oprava rizika, které tam je dnes.

---

## 5. Co uvidí člen

### Trvale: historie konta

Nový řádek „🎁 Sleva z akce: Jesenní Ostrov" (když se vracelo), nebo „➕ Doúčtování akce: Jesenní Ostrov" (když se doplácelo). Při té příležitosti doplním i chybějící popisek pro účtování akcí – dnes se v historii ukazuje holé `event_charge`.

### Dočasně: na hlavní stránce

Pod kontem se objeví kartička:

```
🎁 Vrátili jsme ti 90 Kč
Jesenní Ostrov vyšel levněji, než se čekalo – ubytování 150 → 120 Kč.
Připsáno 19. 10. na tvoje konto.
                                           [ Rozumím ]
```

Při zdražení táž kartička, jen vážnějším tónem a oranžově:

```
➕ Doúčtovali jsme ti 90 Kč
Jesenní Ostrov vyšel dráž, než se čekalo – ubytování 150 → 180 Kč.
Strženo 19. 10. z tvého konta.
                                           [ Rozumím ]
```

- Ukáže se komukoli, komu během **posledních 14 dní** přišla oprava ceny.
- **„Rozumím" ji schová** natrvalo (pamatuje si to prohlížeč, stejně jako seznam zrušených saun). Na jiném zařízení ji do 14 dnů uvidí znovu – spíš dobře než špatně.
- Když přijde víc oprav naráz, ukáže se jedna kartička se součtem a názvy akcí.

---

## 6. Co se nemění

- Vyúčtování členem (do 5 dnů po akci) běží dál stejně.
- Zůstatky se pořád nikdy nezapisují jako číslo, dopočítávají se z transakcí.
- Ceny si bere databáze ze své tabulky – prohlížeč posílá jen nový ceník a ten projde kontrolou (celé číslo, 0 až 100 000, jen admin).
- Zúčtovat akci jde pořád jen jednou. Po zúčtování se ceník touhle cestou už nemění; případnou opravu jednotlivci udělá admin ruční korekcí.

---

## 7. Nasazení

1. **SQL `db/krok14-upravy-cen-pri-zuctovani.sql`** – nová funkce `settle_event` (ceník + stržení + opravy v jedné operaci), typ transakce `event_adjustment`.
2. **Push origin.**

Bez spuštěného kroku 14 se zúčtování chová jako dnes (projede lidi po jednom, bez možnosti měnit ceny) – ověřím to testem proti staré databázi, jako u předchozích kroků.

> Pořád čekají kroky **10, 11, 12 a 13**. Tenhle přijde po nich.

---

## 8. Rozhodnutá místa

1. **Zdražení i zlevnění se chovají stejně** – kdo se vyúčtoval sám, dostane rozdíl na konto nebo mu z konta odejde. Potvrzeno 19. 10. 2026.
2. **Kartička na profilu drží 14 dní** nebo do kliknutí na „Rozumím". Když budeš chtít jinou dobu, je to jedno číslo.
3. **Opravu dostanou jen ti, co se vyúčtovali sami.** Nevyúčtovaným se rovnou strhne nová částka, takže žádnou opravu v historii neuvidí – není co opravovat. Druhá možnost je strhnout jim starou cenu a hned přidat rozdíl, ať to má každý v historii stejně, ale konto to zbytečně rozhýbe dvěma pohyby. Nechávám první variantu.
