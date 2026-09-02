-- ============================================================
-- NaturClimb - KROK 5a: chranene funkce pro cleny
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spusteny kroky 3 a 4.
--
-- Proc: clen se potrebuje prihlasit na trenink, ale nesmi pritom
-- sahnout na cenu, stav zuctovani ani na cizi zaznamy. Zapisuje
-- proto pres tyto funkce, ktere upravi presne to jedno pole -
-- a jen kdyz je trenink otevreny a pred uzaverkou.
--
-- Nic nemaze. Aplikace bezi dal jako ted.
-- ============================================================


-- Uzaverka pro cleny: 21:00 dne treninku (mistniho casu)
create or replace function public.training_is_locked(p_datetime timestamptz, p_status text)
returns boolean
language sql stable
as $$
  select p_status = 'settled'
      or now() > ((p_datetime at time zone 'Europe/Prague')::date + time '21:00')
             at time zone 'Europe/Prague'
$$;


-- ------------------------------------------------------------
-- 1) Jdu / nejdu / bez volby
-- ------------------------------------------------------------
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

  if public.training_is_locked(t.datetime, t.status) then
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


-- ------------------------------------------------------------
-- 2) Cas prijezdu na trenink
-- ------------------------------------------------------------
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

  if public.training_is_locked(t.datetime, t.status) then
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


-- ------------------------------------------------------------
-- 3) Hledam partaka
-- ------------------------------------------------------------
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

  if public.training_is_locked(t.datetime, t.status) then
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


-- ------------------------------------------------------------
-- 4) Rezervace mista v cizim aute
-- ------------------------------------------------------------
create or replace function public.ride_reserve(p_ride_id text, p_reserve boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  mid   text;
  r     public.event_rides%rowtype;
  obsazeno int;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  select * into r from public.event_rides where id = p_ride_id;
  if not found then
    raise exception 'Nabidka spolujizdy neexistuje';
  end if;

  if p_reserve then
    -- uz rezervovano? nic nedelame
    if exists (
      select 1 from jsonb_array_elements(coalesce(r.reservations, '[]'::jsonb)) x
      where x ->> 'memberId' = mid
    ) then
      return;
    end if;

    select count(*) into obsazeno
    from jsonb_array_elements(coalesce(r.reservations, '[]'::jsonb));

    if obsazeno >= coalesce(r.seats, 0) then
      raise exception 'Auto je plne';
    end if;

    update public.event_rides
    set reservations = coalesce(reservations, '[]'::jsonb)
                       || jsonb_build_array(jsonb_build_object('memberId', mid))
    where id = p_ride_id;
  else
    update public.event_rides
    set reservations = coalesce((
      select jsonb_agg(x)
      from jsonb_array_elements(coalesce(reservations, '[]'::jsonb)) x
      where x ->> 'memberId' <> mid
    ), '[]'::jsonb)
    where id = p_ride_id;
  end if;
end
$$;


-- ------------------------------------------------------------
-- 5) Prepocet konta clena ze souctu jeho transakci
-- ------------------------------------------------------------
-- Aplikace potrebuje po zuctovani ulozit novy zustatek. Kdyby smel
-- zustatek zapisovat kdokoli primo, dal by se nastavit na cokoli.
-- Takhle ho jde jen DOPOCITAT ze skutecnych transakci.
create or replace function public.recalc_member_balance(p_member_id text)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  soucet integer;
begin
  if not public.is_sauna_admin() then   -- plati i pro admina
    raise exception 'Nemas opravneni prepocitat konto';
  end if;

  select coalesce(sum(amount), 0) into soucet
  from public.transactions where member_id = p_member_id;

  update public.members set balance = soucet where id = p_member_id;
  return soucet;
end
$$;


-- ------------------------------------------------------------
-- 6) Sauna admin smi zalozit saunovy trenink
-- ------------------------------------------------------------
-- (automaticke generovani pondelni sauny bezi i pod sauna adminem)
drop policy if exists auth_trainings_sauna_insert on public.trainings;
create policy auth_trainings_sauna_insert on public.trainings
  for insert to authenticated
  with check (public.is_sauna_admin() and venue is not null and lower(venue) like '%sauna%');


-- ------------------------------------------------------------
-- Kdo smi funkce volat: jen prihlaseni
-- ------------------------------------------------------------
revoke execute on function public.training_set_attendance(text, text) from public, anon;
revoke execute on function public.training_set_arrival(text, text)    from public, anon;
revoke execute on function public.training_set_partner(text, boolean) from public, anon;
revoke execute on function public.ride_reserve(text, boolean)         from public, anon;
revoke execute on function public.recalc_member_balance(text)         from public, anon;

grant execute on function public.training_set_attendance(text, text) to authenticated;
grant execute on function public.training_set_arrival(text, text)    to authenticated;
grant execute on function public.training_set_partner(text, boolean) to authenticated;
grant execute on function public.ride_reserve(text, boolean)         to authenticated;
grant execute on function public.recalc_member_balance(text)         to authenticated;


-- ------------------------------------------------------------
-- KONTROLA: vsech pet funkci ma existovat
-- ------------------------------------------------------------
select p.proname as funkce, 'OK' as stav
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('training_is_locked','training_set_attendance',
                    'training_set_arrival','training_set_partner','ride_reserve',
                    'recalc_member_balance')
order by 1;
