-- ============================================================
-- NaturClimb - KROK 13: lhuta na vlastni vyuctovani
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 12.
--
-- Co to prinasi:
--   1) Clen se muze sam vyuctovat jeste 5 dni po konci akce.
--      Pak se vyuctovani zavre a zbytek dorovna admin.
--   2) Admin muze u konkretni akce lhutu posunout - treba otevrit
--      vyuctovani zpetne u akce, ktera uz skoncila driv.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================


-- 1) Vlastni termin u akce (prazdny = konec akce + 5 dni) ------------------
alter table public.events
  add column if not exists settlement_deadline timestamptz;

comment on column public.events.settlement_deadline is
  'Do kdy se muze clen sam vyuctovat. NULL = konec akce + 5 dni.';


-- 2) Termin k dane akci ----------------------------------------------------
create or replace function public.event_settlement_deadline(p_event_id text)
returns timestamptz
language sql stable security definer set search_path = public
as $$
  select coalesce(settlement_deadline, end_datetime + interval '5 days')
    from public.events where id = p_event_id;
$$;


-- 3) Vyuctovani clenem hlida lhutu ----------------------------------------
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
  termin timestamptz;
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

  termin := coalesce(e.settlement_deadline, e.end_datetime + interval '5 days');
  if now() > termin then
    raise exception 'Vyuctovani se zavrelo % - ozvi se adminovi',
      to_char(termin at time zone 'Europe/Prague', 'DD.MM.YYYY HH24:MI');
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


-- 4) Admin posune lhutu ----------------------------------------------------
-- p_dni = o kolik dni od ted je vyuctovani jeste otevrene.
-- p_dni = null vrati akci zpet na vychozi pravidlo (konec + 5 dni).
create or replace function public.set_event_settlement_deadline(
  p_event_id text,
  p_dni      integer default 5
)
returns timestamptz
language plpgsql security definer set search_path = public
as $$
declare
  novy timestamptz;
begin
  if not public.is_club_admin() then
    raise exception 'Menit lhutu muze jen admin';
  end if;

  if p_dni is null then
    update public.events set settlement_deadline = null where id = p_event_id;
  else
    if p_dni < 1 or p_dni > 60 then
      raise exception 'Zadej 1 az 60 dni';
    end if;
    novy := date_trunc('minute', now()) + make_interval(days => p_dni);
    update public.events set settlement_deadline = novy where id = p_event_id;
  end if;

  return public.event_settlement_deadline(p_event_id);
end
$$;

revoke execute on function public.set_event_settlement_deadline(text, integer) from public, anon;
grant  execute on function public.set_event_settlement_deadline(text, integer) to authenticated;


-- 5) Jednorazove: akce, ktere uz skoncily driv nez pred peti dny -----------
-- Aby se po spusteni tohohle kroku nikomu vyuctovani nezavrelo pod rukama,
-- dostanou jeste pet dni od ted. Pri druhem spusteni uz se jich to netyka.
update public.events
   set settlement_deadline = date_trunc('minute', now()) + interval '5 days'
 where status <> 'settled'
   and settlement_deadline is null
   and end_datetime + interval '5 days' < now();


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'sloupec settlement_deadline' as co,
       coalesce((select 'existuje' from information_schema.columns
         where table_schema='public' and table_name='events'
           and column_name='settlement_deadline' limit 1), 'CHYBI') as hodnota
union all
select 2, 'akce s otevrenym vyuctovanim',
       (select count(*)::text from public.events
         where status <> 'settled'
           and now() <= coalesce(settlement_deadline, end_datetime + interval '5 days'))
union all
select 3, 'akce, kde uz lhuta probehla',
       (select count(*)::text from public.events
         where status <> 'settled'
           and now() > coalesce(settlement_deadline, end_datetime + interval '5 days'))
order by 1;
