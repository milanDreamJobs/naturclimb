-- ============================================================
-- NaturClimb - KROK 6: pozdejsi uzaverka sauny + zvyhodnena cena za noc
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3, 4 a 5.
--
-- Co to udela:
--   1) Uzaverka prihlasovani na SAUNU se posune z 21:00 na 23:50.
--      (Lezecke treninky zustavaji na 21:00.)
--   2) K akcim pribude druha, zvyhodnena cena za noc - pro deti
--      nebo pro ty, co spi ve vlastnim stanu.
--
-- Nic nemaze, zadna data nemeni.
-- ============================================================


-- 1) Uzaverka: sauna az ve 23:50 -------------------------------------------
create or replace function public.training_is_locked(
  p_datetime timestamptz,
  p_status   text,
  p_venue    text default null
)
returns boolean
language sql stable
as $$
  select p_status = 'settled'
      or now() > (
           (p_datetime at time zone 'Europe/Prague')::date
           + case
               when p_venue is not null and lower(p_venue) like '%sauna%'
                 then time '23:50'
               else time '21:00'
             end
         ) at time zone 'Europe/Prague'
$$;


-- Funkce, ktere uzaverku pouzivaji, musi nove predat i misto konani.
create or replace function public.training_set_attendance(p_training_id text, p_status text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  mid text;
  t   public.trainings%rowtype;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  if p_status not in ('going', 'not_going', 'none') then
    raise exception 'Neplatna volba';
  end if;

  select * into t from public.trainings where id = p_training_id;
  if not found then
    raise exception 'Trenink neexistuje';
  end if;

  if public.training_is_locked(t.datetime, t.status, t.venue) then
    raise exception 'Trenink je uzavreny (zuctovany nebo po uzaverce)';
  end if;

  update public.trainings set
    registrations = case
      when p_status = 'going'
        then (coalesce(registrations, '[]'::jsonb) - mid) || to_jsonb(array[mid])
      else coalesce(registrations, '[]'::jsonb) - mid
    end,
    declined = case
      when p_status = 'not_going'
        then (coalesce(declined, '[]'::jsonb) - mid) || to_jsonb(array[mid])
      else coalesce(declined, '[]'::jsonb) - mid
    end
  where id = p_training_id;
end
$$;


create or replace function public.training_set_arrival(p_training_id text, p_time text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  mid text;
  t   public.trainings%rowtype;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  if p_time is not null and p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'Neplatny cas';
  end if;

  select * into t from public.trainings where id = p_training_id;
  if not found then
    raise exception 'Trenink neexistuje';
  end if;

  if public.training_is_locked(t.datetime, t.status, t.venue) then
    raise exception 'Trenink je uzavreny';
  end if;

  update public.trainings set
    arrival_times = case
      when p_time is null then coalesce(arrival_times, '{}'::jsonb) - mid
      else coalesce(arrival_times, '{}'::jsonb) || jsonb_build_object(mid, p_time)
    end
  where id = p_training_id;
end
$$;


create or replace function public.training_set_partner(p_training_id text, p_seeking boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  mid text;
  t   public.trainings%rowtype;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  select * into t from public.trainings where id = p_training_id;
  if not found then
    raise exception 'Trenink neexistuje';
  end if;

  if public.training_is_locked(t.datetime, t.status, t.venue) then
    raise exception 'Trenink je uzavreny';
  end if;

  update public.trainings set
    looking_for_partner = case
      when p_seeking
        then (coalesce(looking_for_partner, '[]'::jsonb) - mid) || to_jsonb(array[mid])
      else coalesce(looking_for_partner, '[]'::jsonb) - mid
    end
  where id = p_training_id;
end
$$;


-- Stara dvouparametrova verze uz neni potreba
drop function if exists public.training_is_locked(timestamptz, text);


-- 2) Zvyhodnena cena za noc ------------------------------------------------
-- Cena akce zustava "plna cena za noc"; k ni pribyva druha, nizsi sazba
-- pro deti nebo pro spani ve vlastnim stanu.
alter table public.events
  add column if not exists price_accommodation_reduced integer not null default 0;

comment on column public.events.price_accommodation_reduced is
  'Zvyhodnena cena za noc (deti, vlastni stan). 0 = nenabizi se.';

-- U prihlasky vedle poctu plnych noci i pocet zvyhodnenych.
alter table public.event_registrations
  add column if not exists nights_reduced integer not null default 0;

comment on column public.event_registrations.nights_reduced is
  'Pocet noci uctovanych zvyhodnenou sazbou (deti, stan).';


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'uzaverka sauny (ma byt 23:50)' as co,
       to_char(
         (now()::date + time '23:50') at time zone 'Europe/Prague'
         at time zone 'Europe/Prague', 'HH24:MI') as hodnota
union all
select 2, 'events.price_accommodation_reduced',
       coalesce((select 'existuje' from information_schema.columns
         where table_schema='public' and table_name='events'
           and column_name='price_accommodation_reduced'), 'CHYBI')
union all
select 3, 'event_registrations.nights_reduced',
       coalesce((select 'existuje' from information_schema.columns
         where table_schema='public' and table_name='event_registrations'
           and column_name='nights_reduced'), 'CHYBI')
union all
select 4, 'funkci training_* celkem',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname like 'training_%')
order by 1;
