# Funkční specifikace – členské příspěvky (NaturClimb)

Verze 1, 18. 10. 2026. Zapsáno před programováním, ke schválení.

---

## 0. Co je dnes v databázi (odkontrolováno)

Zjištěno dotazem v Supabase:

- `payment_claims` má sloupce `id, member_id, amount, kind, fee_type, year, status, note, created_at, decided_at, decided_by`.
  **Rok se tedy ukládá – ale jen na ohlášené platbě** (`year`, plní se jako kalendářní rok z `now()`).
- `transactions` zná typ `membership_fee`, ale **žádná taková transakce v databázi zatím není** (0 záznamů) – příspěvek přes appku ještě nikdo nezaplatil.
- U člena (`members`) **žádné pole „zaplatil příspěvek" není**.
- Appka dnes „zaplaceno" **hádá**: `maZaplacenyPrispevek()` se dívá, jestli má člen v letošním kalendářním roce transakci typu `membership_fee` **nebo jakoukoli platbu ≥ 500 Kč**.

Z toho plynou dvě dnešní slabiny, které tahle úprava odstraní:

1. **Falešná zelená** – kdo si dobije konto 600 Kč na pivo, svítí jako zaplacený příspěvek.
2. **Kalendářní rok vs. sezóna** – ty chceš razítko „2026/27", což je sezóna, ne kalendářní rok.

---

## 1. Období příspěvku: sezóna

Zavedu pojem **sezóna příspěvků**:

- V nastavení klubu bude **„Sezóna příspěvků začíná měsícem"**, výchozí hodnota **9 (září)**.
- Sezóna 2026/27 pak znamená 1. 9. 2026 – 31. 8. 2027. Dnes (18. 10. 2026) běží sezóna **2026/27**.
- V databázi se sezóna ukládá jako **jedno číslo = rok jejího začátku** (2026). Popisek „2026/27" se z něj jen vykresluje.
- Kdyby sis to rozmyslel a chtěl kalendářní rok, přepneš v nastavení měsíc na **1** a popisky se samy změní na „2026". Nic se nepřeprogramovává.

*Tohle je jediné rozhodnutí, kde jsem volil za tebe – vycházím z tvého „příspěvky zaplaceny 2026/27". Měníš jedním polem v nastavení.*

---

## 2. Zaplaceno = záznam, ne odhad

Nová tabulka **`membership_fees`**: jeden řádek = jeden člen × jedna sezóna.

| sloupec | význam |
|---|---|
| `member_id` | člen |
| `season_year` | 2026 (= sezóna 2026/27) |
| `fee_type` | `full` / `reduced` |
| `amount` | kolik skutečně zaplatil |
| `paid_at` | kdy to admin potvrdil |
| `claim_id` | z jaké ohlášené platby to vzniklo (nebo prázdné u hotovosti) |
| `created_by` | který admin to potvrdil |

Unikátní na `(member_id, season_year)` – dvakrát za sezónu to nejde zapsat omylem.

Řádek vzniká **jen dvěma cestami**:

1. Admin potvrdí ohlášenou platbu, která obsahuje příspěvek.
2. Admin ručně zaškrtne „zaplaceno v hotovosti" (nová funkce, chráněná, jen hlavní admin).

Admin to může i vzít zpět (překlik, omyl) – pak řádek zmizí a puntík zčervená. Transakce na kontě se tím **nemaže**, ty se řeší zvlášť v historii konta.

Appka pak „zaplaceno" **nehádá** – jen se podívá, jestli řádek existuje. Staré chování (platba ≥ 500 Kč = zelená) **padá**, protože dělalo falešně zelené puntíky.

---

## 3. Dialog „Zaplatil jsem na oddílový účet" – příspěvek i dobití dohromady

Dnes jsou tři tlačítka a vybereš jedno. Nově:

- **„Co platíš?"** jsou **zaškrtávací** položky, dají se vybrat obě:
  - 🎫 Roční příspěvek **800 Kč** (nebo zvýhodněný **500 Kč** – pořád jen jedna sazba z těch dvou)
  - 💰 Dobití konta – s **vlastním políčkem na částku** (předplní se dluh, jde přepsat)
- **„Částka celkem"** se **sama počítá** jako příspěvek + dobití a je **jen ke čtení** (nejde ji rozhodit překlepem proti tomu, co je zaškrtnuté).
  - Příklad: zvýhodněný příspěvek 500 + dobití 1 000 → „Celkem 1 500 Kč".
- **QR kód** se generuje z celkové částky, takže člen platí **jedním převodem**.
- Když zaškrtne jen dobití, chová se to přesně jako dnes.
- Pod součtem bude drobným řádek typu: *„Z toho příspěvek 500 Kč (sezóna 2026/27), dobití konta 1 000 Kč."*

Ohlášená platba se v databázi rozpadne na dvě čísla: `fee_amount` a `topup_amount` (součet = `amount`). Proto **poznáš, že v platbě byl příspěvek**, i když přišla jedna částka.

### Co uvidí admin u potvrzování

```
Milan Mahovský          1 500 Kč   [Potvrdit] [Zamítnout]
🎫 příspěvek 500 Kč (zvýhodněný, 2026/27) + 💰 dobití 1 000 Kč
```

Po potvrzení se stane **všechno naráz, jedním krokem**:

- zapíše se příspěvek 500 Kč do `membership_fees` (sezóna 2026/27) – **na konto se nepřipisuje**, konto se tím nezvedne,
- vznikne transakce `bank_deposit` 1 000 Kč – **jen dobití** se připíše na konto,
- puntík zezelená a členovi naskočí razítko.

**Příspěvek nejde na konto** (rozhodnuto 18. 10. 2026). Konto je dál jen na tréninky, pivo a akce – zaplacený příspěvek ho nezvedne, člen za něj nemá co propit. Jediné, co se za příspěvek „koupí", je razítko. V přehledu *Moje konto* se příspěvek **neobjeví ani jako položka v historii**; eviduje se zvlášť (v detailu člena v adminu uvidíš „příspěvek 2026/27, 500 Kč, potvrzeno 18. 10.").

---

## 4. Hlavní stránka člena

### Když má zaplaceno

Vedle jména v hlavičce („Ahoj Milane! 👋") přibude razítko:

```
✓ Příspěvky zaplaceny 2026/27
```

Zelené, drobné, bez proklikávání. Na mobilu se zlomí pod jméno, aby nic nepřetékalo.

### Když nemá zaplaceno – výzva

Nad tlačítkem „Zaplatil jsem na oddílový účet" se objeví karta:

```
🎫 Je čas zaplatit členské příspěvky
   Sezóna 2026/27 · 800 Kč, zvýhodněný 500 Kč
   [ Zaplatit příspěvek → ]
```

Kliknutí **otevře stejný dialog platby s předvybraným příspěvkem** (plná sazba; přepnutí na zvýhodněnou je jeden klik). Výzva svítí, dokud není zaplaceno, a zmizí ve chvíli, kdy admin platbu potvrdí. Když má člen příspěvek ohlášený a čeká na potvrzení, místo výzvy se zobrazí „⏳ příspěvek ohlášen, čeká na potvrzení" – ať to lidi neposílají dvakrát.

---

## 5. Admin: přehled, kdo zaplatil

V Admin → Členové přibude nad seznam přepínač:

```
[ Všichni 67 ]  [ ✓ Zaplaceno 41 ]  [ ✗ Nezaplaceno 26 ]     Sezóna 2026/27 ▾
```

- Filtr jde kombinovat s hledáním, které tam už je.
- U každého člena v seznamu zůstává puntík (zelený/červený), nově je ale **pravdivý** – podle `membership_fees`, ne podle náhodné platby.
- Přepínač sezóny (letošní / předchozí) – ať se dá dohledat, kdo loni zaplatil a letos ne.
- Nad filtrovaným seznamem „Nezaplaceno" budou dvě akce:
  - **📋 Kopírovat e-maily** – do schránky, abys mohl rozeslat upomínku,
  - u člena v detailu **✓ Zaplatil v hotovosti** – zapíše příspěvek bez ohlášené platby (a dá se vzít zpět).

Vidí to **jen hlavní admin**, ne sauna admin.

---

## 6. Vyúčtování akce: filtr nezúčtovaných

V detailu akce u seznamu přihlášených přibude přepínač:

```
[ Všichni 35 ]  [ ⏳ Nezúčtovaní 12 ]  [ 🧾 Zúčtovaní sami 23 ]
```

- „Nezúčtovaní" = kdo si **sám** nekliknul vyúčtování (`settled_at` je prázdné) – to jsou přesně ti, které musíš projít ručně.
- Filtr je jen zobrazovací, nic nepřepočítává. Hromadné „Zúčtovat akci" funguje dál stejně a lidi, co se zúčtovali sami, přeskakuje (to už dnes platí).

---

## 7. Postup nasazení (pořadí se nemění)

1. **SQL `db/krok11-prispevky-sezona.sql`** – pustíš v Supabase SQL Editoru. Nic nemaže, jen přidává. Obsahuje i jednorázové dohledání: pokud se najde potvrzená příspěvková platba z minulosti, doplní se k ní řádek v `membership_fees`.
2. **Push origin** v GitHub Desktopu.

Appka bude napsaná tak, že **když SQL ještě nepustíš, nic se nerozbije** – razítko a filtry se prostě neukážou a dialog platby se zachová jako dnes (jedna položka). To otestuju i proti staré databázi, stejně jako u předchozích kroků.

> Ještě visí **krok 10** (`db/krok10-jedna-prihlaska.sql`) – ten pusť dřív než krok 11.

---

## 8. Co dělám a co nedělám

**Dělám:**

- sloučenou platbu příspěvek + dobití s jedním QR kódem,
- sezónní evidenci příspěvků jako skutečný záznam v databázi,
- razítko „Příspěvky zaplaceny 2026/27" u jména,
- výzvu k zaplacení s proklikem do dialogu,
- admin přehled s filtrací zaplaceno/nezaplaceno + kopii e-mailů + ruční hotovost,
- filtr nezúčtovaných u akce.

**Nedělám** (není v zadání, řekni jestli chceš):

- hromadné „naúčtovat příspěvky všem" jedním tlačítkem (mluvili jsme o tom dřív),
- automatické e-mailové upomínky nezaplaceným,

---

## 9. Potvrzená rozhodnutí

- **Sezóna začíná zářím** – potvrzeno 18. 10. 2026. Dnešní sezóna je **2026/27** (1. 9. 2026 – 31. 8. 2027). V nastavení zůstane pole se začátkem sezóny, aby se to dalo kdykoli přepnout.
- **Příspěvek nejde na konto** – potvrzeno 18. 10. 2026. Viz bod 3.

---

## 10. Co bylo otestováno (18. 10. 2026)

**Databáze – 43 testů proti skutečnému PostgreSQL** (lokální kopie schématu, kroky 7, 8 a 11 spuštěné po sobě):

- sezóna se počítá správně (říjen + start září = 2026/27; start prosinec = 2025/26; start leden = kalendářní rok),
- složená platba 500 + 1000 se uloží jako 1500 s rozpadem,
- **sazbu si bere databáze z nastavení, klient ji neposlá** – nikdo si nemůže ohlásit příspěvek za 1 Kč,
- po potvrzení jde na konto **jen dobití**, příspěvek nikoli (0 transakcí typu membership_fee),
- druhý příspěvek na tu samou sezónu databáze odmítne, dobití konta jde dál,
- potvrdit, zapsat nebo smazat příspěvek **nemůže nikdo kromě admina** (zkoušeno za obyčejného člena – odmítnuto),
- jeden řádek na člena a sezónu drží unikátní index,
- stará funkce `claim_payment` (kdyby někomu v prohlížeči visívala stará verze appky) funguje a směřuje do nové evidence,
- **krok 11 se dá pustit dvakrát** – podruhé neže nic nezmění (stejné počty, žádné duplicity).

**Appka – 92 testů v prohlížeči** (Playwright + napodobenina databáze):

- výzva, razítko, dialog platby (obojí naráz, jen příspěvek, jen dobití, nic nezaškrtnuto, už zaplaceno),
- QR kód nese **celkovou** částku,
- admin: filtry zaplaceno/nezaplaceno, přepínání sezón, kopie e-mailů, ruční zápis hotovosti i jeho vrácení,
- **hledání člena neobejde filtr** (to byla past, na kterou appka dřív šla),
- filtr nezúčtovaných u akce,
- **chování proti staré databázi** (SQL krok 11 nespuštěný): nic se nerozbije, dialog zůstane starý, nastavení neposlá ne‑existující sloupec,
- regrese: tréninky, přihlášky na akci, vyúčtování členem, historie konta a všechny admin záložky se vykreslí bez chyby.
