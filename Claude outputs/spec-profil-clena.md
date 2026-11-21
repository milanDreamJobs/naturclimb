# Spec: Profil člena — osobní data, styl lezení, obtížnost, fotka

**Stav:** Schváleno Milanem 2026-11-17 — připraveno k implementaci

---

## Filozofie

Každý člen má volitelný profil — zapíše si, jak leze, jakou obtížnost a co ho baví. Admin vidí profily všech. Profil slouží pro přehled oddílu a párování lezeckých partnerů.

---

## Co profil obsahuje

### Základní info
- **Lezu od** — rok zahájení (int, např. 2019)
- **Popis sebe** — volný text, max 300 znaků
- **Preferované lokality** — volný text, max 200 znaků

### Kde lezu — styl + úroveň + přání (pro každý styl zvlášť)

Pro každý ze 7 stylů lezení: checkbox (leze / neleze), hvězdičky 1–10 (úroveň), checkbox „chci víc" a checkbox „uvítám mentora".

| Styl | Leze? | Úroveň 1–10 | Chci víc | Uvítám mentora |
|---|---|---|---|---|
| Lezu jen na prvním | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |
| Lezu TOP rope | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |
| Písek | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |
| Boulder | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |
| Sport | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |
| Vícedélky | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |
| Ledy / mixy | ☐ | ★☆☆☆☆☆☆☆☆☆ | ☐ | ☐ |

Hvězdičky a checkboxy „chci víc" / „uvítám mentora" se zobrazí vždy (nezávisle na zaškrtnutém stylu).

### Obtížnost
- Jeden volný text, placeholder "např. 7a sport, 7B boulder, WI4"
- Max 50 znaků

### Celková úroveň — hvězdičky 1–10
- Jedno globální hodnocení vlastní úrovně (1 = úplný začátečník, 10 = extrémní lezec)
- Interaktivní klikatelné hvězdičky

### Fotka profilu
- Upload fotky (avatar)
- Uložena do Supabase Storage (bucket `avatars`), veřejná URL
- Max 2 MB, formáty jpg/png/webp
- Pokud nevyplněna — initials avatar (první písmeno jména)

---

## Datový model — nová tabulka `member_profiles`

```sql
CREATE TABLE IF NOT EXISTS member_profiles (
  id              text PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
  updated_at      timestamptz DEFAULT now(),

  -- Základní info
  year_started    int,
  bio             text,
  preferred_areas text,

  -- Styl lezení: leze / úroveň / chci víc / uvítám mentora
  style_firstlead         boolean DEFAULT false,
  style_firstlead_rating  smallint CHECK (style_firstlead_rating BETWEEN 1 AND 10),
  style_firstlead_more    boolean DEFAULT false,
  style_firstlead_mentor  boolean DEFAULT false,

  style_toprope           boolean DEFAULT false,
  style_toprope_rating    smallint CHECK (style_toprope_rating BETWEEN 1 AND 10),
  style_toprope_more      boolean DEFAULT false,
  style_toprope_mentor    boolean DEFAULT false,

  style_pisek             boolean DEFAULT false,
  style_pisek_rating      smallint CHECK (style_pisek_rating BETWEEN 1 AND 10),
  style_pisek_more        boolean DEFAULT false,
  style_pisek_mentor      boolean DEFAULT false,

  style_boulder           boolean DEFAULT false,
  style_boulder_rating    smallint CHECK (style_boulder_rating BETWEEN 1 AND 10),
  style_boulder_more      boolean DEFAULT false,
  style_boulder_mentor    boolean DEFAULT false,

  style_sport             boolean DEFAULT false,
  style_sport_rating      smallint CHECK (style_sport_rating BETWEEN 1 AND 10),
  style_sport_more        boolean DEFAULT false,
  style_sport_mentor      boolean DEFAULT false,

  style_multipitch        boolean DEFAULT false,
  style_multipitch_rating smallint CHECK (style_multipitch_rating BETWEEN 1 AND 10),
  style_multipitch_more   boolean DEFAULT false,
  style_multipitch_mentor boolean DEFAULT false,

  style_ice               boolean DEFAULT false,
  style_ice_rating        smallint CHECK (style_ice_rating BETWEEN 1 AND 10),
  style_ice_more          boolean DEFAULT false,
  style_ice_mentor        boolean DEFAULT false,

  -- Obtížnost
  grade           text,

  -- Celková úroveň
  skill_rating    smallint CHECK (skill_rating BETWEEN 1 AND 10),

  -- Fotka
  avatar_url      text
);
```

RLS: člen čte/píše jen svůj řádek (`id = auth_member_id()`). Admin čte vše.

SQL krok: **krok18** (nový soubor `krok18-profil-clena.sql`)

---

## State a načítání

```js
state.profile = null;
state.profileReady = false;
```

```js
async function loadProfile() {
  if (!state.currentUserId) return;
  const { data, error } = await db
    .from('member_profiles')
    .select('*')
    .eq('id', state.currentUserId)
    .maybeSingle();
  if (error?.code === '42P01') { state.profileReady = false; return; }
  state.profileReady = true;
  state.profile = data || {};
}
```

Volat v `initApp()` po `loadMember()`.

---

## UI — pohled člena (`renderMember()`)

Nová sekce **„Můj profil"** — umístění: pod Přehledem účtu, před FAQ.
Zobrazit jen pokud `state.profileReady === true`.

```
╔══════════════════════════════════════════════════════╗
║  👤 Můj profil                                       ║
╠══════════════════════════════════════════════════════╣
║                                                      ║
║  [Avatar 60×60]  Nahrát fotku →                      ║
║                                                      ║
║  Lezu od: [____]                                     ║
║                                                      ║
║  O sobě:  [__________________________________]       ║
║                                                      ║
║  Preferované lokality: [_____________________]       ║
║                                                      ║
║  Kde lezu:                                           ║
║  ┌─────────────────────────────────────────────┐    ║
║  │ ☐ Lezu jen na prvním                        │    ║
║  │    Úroveň: ☆☆☆☆☆☆☆☆☆☆                    │    ║
║  │    ☐ Chci víc   ☐ Uvítám mentora           │    ║
║  ├─────────────────────────────────────────────┤    ║
║  │ ☐ Lezu TOP rope                             │    ║
║  │    Úroveň: ☆☆☆☆☆☆☆☆☆☆                    │    ║
║  │    ☐ Chci víc   ☐ Uvítám mentora           │    ║
║  ├─────────────────────────────────────────────┤    ║
║  │ ☐ Písek                                     │    ║
║  │    Úroveň: ☆☆☆☆☆☆☆☆☆☆                    │    ║
║  │    ☐ Chci víc   ☐ Uvítám mentora           │    ║
║  ├─────────────────────────────────────────────┤    ║
║  │ ☐ Boulder / ☐ Sport / ☐ Vícedélky / ☐ Ledy │    ║
║  │    (stejný vzor)                            │    ║
║  └─────────────────────────────────────────────┘    ║
║                                                      ║
║  Obtížnost: [________________________________]       ║
║  (volný text, např. 7a sport, 7B boulder, WI4)       ║
║                                                      ║
║  Celková úroveň:                                     ║
║  ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆  (1–10)                     ║
║  1 = začátečník … 10 = extrémní lezec                ║
║                                                      ║
║               [Uložit profil]                        ║
╚══════════════════════════════════════════════════════╝
```

### Hvězdičky 1–10 (každý styl i celková úroveň)
- Klikatelné — klik na 7. = hodnota 7
- ★ = vyplněná (žlutá), ☆ = prázdná (šedá)
- NULL = všechny šedé

### „Chci víc" a „Uvítám mentora"
- Zobrazovat vždy u každého stylu
- „Chci víc" = chce se v tomto stylu zlepšovat, hledá příležitosti
- „Uvítám mentora" = hledá zkušenějšího člena, který mu pomůže

---

## UI — admin pohled

V detailu člena přibyde sekce **„Lezecký profil"**:

```
[Avatar]  Jan Novák — leze od 2019
Celková úroveň: ★★★★★★★☆☆☆  7/10

Kde leze:
  Sport      ★★★★★★☆☆☆☆  6/10   chce víc
  Boulder    ★★★★☆☆☆☆☆☆  4/10   uvítá mentora
  Vícedélky  ★★☆☆☆☆☆☆☆☆  2/10   chce víc · uvítá mentora

Obtížnost: 7a sport, 6b+ přirozenost
O sobě: "Jezdím hlavně na Adršpach a do Alp."
Lokality: Adršpach, Alpy
```

Admin profil nemůže editovat.

---

## Fáze dodání

**Fáze 1:** Profil bez fotky — základní info, styl + úroveň + chci víc + mentor, obtížnost, celková úroveň.

**Fáze 2:** Fotka profilu — Supabase Storage, initials fallback.

**Fáze 3 (volitelné):** Integrace s partnerstvím — zobrazit styl + obtížnost u „Hledám parťáka".

---

## Co se NEMĚNÍ

- Přihlašování, bilance, registrace tréninků — beze změny
- Vybavení — v profilu není
- Profil je volitelný — nevyplněný profil nevadí ničemu
