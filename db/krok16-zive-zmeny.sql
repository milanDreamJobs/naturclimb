-- ============================================================
-- NaturClimb - KROK 16: zive zmeny (Supabase Realtime)
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 15.
--
-- Proc: appka si data stahne pri prihlaseni. Kdo necha zalozku otevrenou,
-- diva se na stary stav - clen videl "ceka na potvrzeni" u platby, kterou
-- admin uz davno potvrdil. Timhle krokem zacne databaze posilat zmeny
-- rovnou do otevrenych prohlizecu a appka se prekresli sama.
--
-- Co to NEzmeni: kdo co smi videt. Realtime posila zmeny pres stejna
-- pravidla (RLS) jako obycejne cteni - clen tedy dal vidi jen sve platby.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================

do $$
declare
  tabulka text;
  seznam  text[] := array[
    'members',               -- zustatek na konte
    'transactions',          -- pohyby
    'payment_claims',        -- ohlasene platby a jejich potvrzeni
    'membership_fees',       -- zaplacene prispevky (razitko)
    'trainings',             -- prihlasky na treninky
    'events',                -- akce
    'event_registrations'    -- prihlasky na akce
  ];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach tabulka in array seznam loop
    if to_regclass('public.' || tabulka) is null then
      raise notice 'tabulka % neexistuje, preskakuji', tabulka;
      continue;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = tabulka
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tabulka);
      raise notice 'pridano: %', tabulka;
    end if;
  end loop;
end $$;


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'tabulek posila zive zmeny' as co,
       (select count(*)::text from pg_publication_tables
         where pubname = 'supabase_realtime' and schemaname = 'public') as hodnota
union all
select 2, 'ktere to jsou',
       (select string_agg(tablename, ', ' order by tablename) from pg_publication_tables
         where pubname = 'supabase_realtime' and schemaname = 'public')
order by 1;
