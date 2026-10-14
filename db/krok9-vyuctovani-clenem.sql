-- ============================================================
-- NaturClimb - KROK 9: clen si po akci sam potvrdi skutecnou utratu
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 8.
--
-- Jak to funguje:
--   Po skonceni akce clovek otevre stejny formular jako u prihlasky,
--   upravi, co doopravdy snedl a vypil, a potvrdi. Castku spocita
--   databaze z ulozenych cen akce (ne z toho, co posle prohlizec),
--   zalozi transakci a oznaci prihlasku za vyuctovanou.
--
--   Admin pak pri zuctovani akce preskoci ty, kdo se vyuctovali sami,
--   takze se nikomu neodecte dvakrat.
-- ============================================================


-- 1) Stopa o vyuctovani u prihlasky ---------------------------------------
alter table public.event_registrations
  add column if not exists settled_at     timestamptz;
alter table public.event_registrations
  add column if not exists settled_amount integer;

comment on column public.event_registrations.settled_at is
  'Kdy si clen sam potvrdil skutecnou utratu. NULL = jeste nevyuctovano.';


-- 2) Vyuctovani clenem -----------------------------------------------------
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
declare
  mid    text;
  e      public.events%rowtype;
  r      public.event_registrations%rowtype;
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
  p_beer1          := greatest(0, least(coalesce(p_beer1, 0), 200));
  p_beer2          := greatest(0, least(coalesce(p_beer2, 0), 200));

  select * into e from public.events where id = p_event_id;
  if not found then
    raise exception 'Akce neexistuje';
  end if;
  if e.status = 'settled' then
    raise exception 'Akci uz zuctoval admin';
  end if;
  if now() < e.end_datetime then
    raise exception 'Akce jeste neskoncila';
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
          + p_beer1          * coalesce(e.beer1_price, 0)
          + p_beer2          * coalesce(e.beer2_price, 0);

  update public.event_registrations
     set nights         = p_nights,
         nights_reduced = p_nights_reduced,
         beer1_count    = p_beer1,
         beer2_count    = p_beer2,
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

revoke execute on function public.settle_my_event_registration(text, integer, integer, integer, integer) from public, anon;
grant  execute on function public.settle_my_event_registration(text, integer, integer, integer, integer) to authenticated;


-- 3) Clen uz nesmi menit prihlasku, kterou si vyuctoval --------------------
drop policy if exists auth_evreg_own on public.event_registrations;
create policy auth_evreg_own on public.event_registrations
  for all to authenticated
  using (member_id = public.current_member_id() and settled_at is null)
  with check (member_id = public.current_member_id() and settled_at is null);


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'sloupce settled_at / settled_amount' as co,
       (select count(*)::text from information_schema.columns
         where table_schema='public' and table_name='event_registrations'
           and column_name in ('settled_at','settled_amount')) || ' z 2' as hodnota
union all
select 2, 'funkce settle_my_event_registration',
       coalesce((select 'existuje' from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='settle_my_event_registration' limit 1), 'CHYBI')
order by 1;
