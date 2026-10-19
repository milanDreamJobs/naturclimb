# Poznámky k vývoji NaturClimb

Krátký zápis pravidel a pastí, aby se chyby neopakovaly. Platí pro `index.html` (celá appka v jednom souboru) a `map.html`.

## Nasazení

1. **Nejdřív SQL** – soubor z `db/` pustit v Supabase → SQL Editor.
2. **Pak Push origin** v GitHub Desktopu.

Každá nová funkce musí **bezpečně degradovat**, dokud její SQL neběželo: chybu jen zaloguj, appka se musí načíst a funkce zůstane tiše schovaná. Testuje se to simulací starého schématu.

## Postup při změně

1. Python read-modify-write s `assert count == 1` na každý vzor (bezpečnější než `sed` na diakritice).
2. **Zapisovat přes dočasný soubor a pak přesunout.** `io.open(cesta, 'w')` soubor usekne hned při otevření – když zápis spadne (např. na kódování), zůstane prázdný `index.html`.
3. Kontrola syntaxe: vytáhnout obsah `<script>` a `node --check`.
4. Playwright headless + ručně napsaný mock Supabase klienta (`window.supabase.createClient`) – projet přihlášení, akci člena, akci admina, zúčtování i částky, které z toho vyjdou. Plus varianta se **starým schématem**.
5. SQL se dá otestovat naostro: v sandboxu je PostgreSQL 16 (`/usr/lib/postgresql/16/bin`), `initdb` nesmí běžet jako root – založit běžného uživatele. Minimální napodobenina schématu + `krok7` … `krok11` za sebou a pak testy přes `DO`/`raise exception`. Odchytí syntaxi i chování (oprávnění, unikátní indexy, idempotenci).
6. Migrace musí jít pustit **dvakrát** bez změny výsledku.

## Pasti, které už kously

- Supabase klient se **musí** jmenovat `db`; `supabase` koliduje s globální proměnnou z CDN.
- `const state` na úrovni skriptu **není** na `window` – v `page.evaluate()` se na něj odkazuj přímo jako `state`, ne `window.state`.
- Escapy `\uXXXX` pro emoji jsou **surrogate páry** – při převodu na znaky řeš nejdřív páry, jinak vznikne rozbitý soubor.
- Hledání člena v adminu (`filterMembers`) přepisuje `style.display` všem řádkům v seznamu. Filtr, který se dělá při renderu, proto musí řádky **vynechat z pole**, ne je schovávat – jinak je hledání odmaskuje.
- Uzávěrky jsou na dvou místech: `isPastDeadline()` v appce a `training_is_locked()` v databázi. Měnit obě.
- Cena se nesmí protáhnout `formatKc()` – přidává plus, takže ceník ukazuje „+800 Kč".
- ISO čas usekaný na 16 znaků je UTC – do `datetime-local` převádět na místní čas (`toLocalInput()`).
- Automatické odeslání kódu po pevném počtu číslic se rozbije při změně délky kódu – odesílat až na plné délce.
- Tiché chyby při ukládání = „zmizelé přihlášky". Každá ukládací funkce musí vrátit úspěch/neúspěch a volající při chybě **vrátit stav zpět** a nechat dialog otevřený.
- V testech `textContent('body')` obsahuje i **zdroják `<script>`** – kontrola na text pak projde, i když se nic nevykreslilo. Číst jen `#app` nebo obsah modálu (`#modal-overlay .modal`).
- Lhůty a termíny platí na dvou místech (appka + databáze). Když se zavádí nová lhůta zpětně, musí migrace **jednorázově dorovnat stará data**, jinak se lidem funkce zavře pod rukama.
- `git` v připojené složce po commitu neumí smazat své `.lock` soubory, dokud není povolené mazání – jinak GitHub Desktop zatuhne.
- V shellu připojeného počítače není nastavená git identita – commitovat přes `git -c user.name=… -c user.email=…` stejnou, jakou mají předchozí commity.

## Zásady

- Zůstatek se nikdy neukládá jako číslo – `recalc_member_balance()` ho počítá z transakcí.
- Zápisy členů jdou výhradně přes `SECURITY DEFINER` funkce. Ceny, zůstatky ani cizí řádky nesmí jít změnit zvenku – ověřuje se to empiricky: přihlásit se jako běžný člen a zkusit to.
- Sazby a částky si bere databáze z `settings` sama, klient je neposílá.
