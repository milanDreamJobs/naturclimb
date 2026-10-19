-- ============================================================
-- NaturClimb - KROK 12: az 6 polozek u akce
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 11.
--
-- Co to prinasi:
--   1) Akce muze mit az 6 polozek (pivo, limonada, vino, snidane...).
--      Prvni dve jsou stavajici beer1 / beer2, pribyvaji polozky 3-6.
--      Co admin nevyplni, se u akce nezobrazi.
--   2) Vyuctovani clenem pocita se vsemi sesti polozkami. Ceny si
--      databaze bere ze sve tabulky, klient posila jen pocty.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================


-- 1) Polozky 3-6 u akce ----------------------------------------------------
alter table public.events add column if not exists item3_name  text;
alter table public.events add column if not exists item3_price integer not null default 0;
alter table public.events add column if not exists item4_name  text;
alter table public.events add column if not exists item4_price integer not null default 0;
alter table public.events add column if not exists item5_name  text;
alter table public.events add column if not exists item5_price integer not null default 0;
alter table public.events add column if not exists item6_name  text;
alter table public.events add column if not exists item6_price integer not null default 0;


-- 2) Jejich pocty u prihlasky ----------------------------------------------
alter table public.event_registrations add column if not exists item3_count integer not null default 0;
alter table public.event_registrations add column if not exists item4_count integer not null default 0;
alter table public.event_registrations add column if not exists item5_count integer not null default 0;
alter table public.event_registrations add column if not exists item6_count integer not null default 0;


-- 3) Vyuctovani clenem se vsemi polozkami ----------------------------------
-- Pocty prichazeji jako pole sesti cisel (poradi = polozka 1..6).
create or replace function public.settle_my_event_registration(
  p_event_id       text,
  p_nights         integer,
  p_nights_reduced integer,
  p_counts         integer[]
)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  mid    text;
  e      public.events%rowtype;
  r      public.event_registrations%rowtype;
  c      integer[] := array[0,0,0,0,0,0];
  i      integer;
  castka integer;
  popis  text;
  tx_id  text;
  novy   integer;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  -- rozumne meze, at se preklepem nevyrobi nesmysl
  p_nights         := greatest(0, least(coalesce(p_nights, 0), 60));
  p_nights_reduced := greatest(0, least(coalesce(p_nights_reduced, 0), 60));
  for i in 1..6 loop
    c[i] := greatest(0, least(coalesce(p_counts[i], 0), 200));
  end loop;

  select * into e from public.events where id = p_event_id;
  if not found then
    raise exception 'Akce neexistuje';
  end if;
  if e.status = 'settled' then
    raise exception 'Akci uz zuctoval admin';
  end if;
  select * into r from public.event_registrations
   where event_id = p_event_id and member_id = mid;
  if not found then
    raise exception 'Nejsi na tuhle akci prihlaseny';
  end if;
  if r.settled_at is not null then
    raise exception 'Uz mas vyuctovano';
  end if;

  -- ceny bere databaze ze sve vlastni tabulky
  castka := p_nights         * coalesce(e.price_accommodation, 0)
          + p_nights_reduced * coalesce(e.price_accommodation_reduced, 0)
          + c[1] * coalesce(e.beer1_price, 0)
          + c[2] * coalesce(e.beer2_price, 0)
          + c[3] * coalesce(e.item3_price, 0)
          + c[4] * coalesce(e.item4_price, 0)
          + c[5] * coalesce(e.item5_price, 0)
          + c[6] * coalesce(e.item6_price, 0);

  update public.event_registrations
     set nights         = p_nights,
         nights_reduced = p_nights_reduced,
         beer1_count    = c[1],
         beer2_count    = c[2],
         item3_count    = c[3],
         item4_count    = c[4],
         item5_count    = c[5],
         item6_count    = c[6],
         settled_at     = now(),
         settled_amount = castka,
         updated_at     = now()
   where id = r.id;

  if castka > 0 then
    popis := 'Akce: ' || e.name || ' (vlastni vyuctovani)';

    select coalesce(sum(amount), 0) - castka into novy
      from public.transactions where member_id = mid;

    tx_id := 'tx_' || replace(gen_random_uuid()::text, '-', '');

    insert into public.transactions
      (id, member_id, amount, type, description, balance_after, created_by, created_at)
    values
      (tx_id, mid, -castka, 'event_charge', popis, novy, mid, now());

    update public.members set balance = novy where id = mid;
  end if;

  return castka;
end
$$;

revoke execute on function public.settle_my_event_registration(text, integer, integer, integer[]) from public, anon;
grant  execute on function public.settle_my_event_registration(text, integer, integer, integer[]) to authenticated;


-- 4) Stara podoba funkce zustava funkcni -----------------------------------
-- (kdyby nekomu v prohlizeci visela starsi verze appky)
create or replace function public.settle_my_event_registration(
  p_event_id       text,
  p_nights         integer,
  p_nights_reduced integer,
  p_beer1          integer,
  p_beer2          integer
)
returns integer
language plpgsql security definer set search_path = public
as $$
begin
  return public.settle_my_event_registration(
    p_event_id, p_nights, p_nights_reduced,
    array[coalesce(p_beer1, 0), coalesce(p_beer2, 0), 0, 0, 0, 0]
  );
end
$$;

revoke execute on function public.settle_my_event_registration(text, integer, integer, integer, integer) from public, anon;
grant  execute on function public.settle_my_event_registration(text, integer, integer, integer, integer) to authenticated;


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'nove sloupce u akci (ceka se 8)' as co,
       (select count(*)::text from information_schema.columns
         where table_schema='public' and table_name='events'
           and column_name in ('item3_name','item3_price','item4_name','item4_price',
                               'item5_name','item5_price','item6_name','item6_price')) as hodnota
union all
select 2, 'nove sloupce u prihlasek (ceka se 4)',
       (select count(*)::text from information_schema.columns
         where table_schema='public' and table_name='event_registrations'
           and column_name in ('item3_count','item4_count','item5_count','item6_count'))
union all
select 3, 'podoby funkce settle_my_event_registration (ceka se 2)',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname='public' and p.proname='settle_my_event_registration')
order by 1;
