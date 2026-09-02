-- ============================================================
-- NaturClimb - KROK 3: vazba clenu na overene ucty
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
--
-- Co to udela: PRIDA sloupec a nekolik funkci.
-- Co to NEudela: nic nemaze, nic neprepisuje, na existujici data nesaha.
-- Aplikace po spusteni bezi dal presne jako ted.
-- ============================================================


-- 1) Sloupec, ktery spoji clena s jeho overenym prihlasenim -----------------
alter table public.members
  add column if not exists auth_id uuid unique references auth.users(id) on delete set null;

comment on column public.members.auth_id is
  'Vazba na overeny ucet (auth.users). NULL = clen se jeste nikdy neprihlasil.';


-- 2) Kdo je prave prihlaseny -----------------------------------------------
create or replace function public.current_member_id()
returns text
language sql stable security definer set search_path = public
as $$
  select id from public.members
  where auth_id = auth.uid() and coalesce(is_active, true)
  limit 1
$$;


-- 3) Je to vubec clen klubu? -----------------------------------------------
create or replace function public.is_club_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.members
    where auth_id = auth.uid() and coalesce(is_active, true)
  )
$$;


-- 4) Je to admin? ----------------------------------------------------------
create or replace function public.is_club_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select is_admin from public.members
    where auth_id = auth.uid() and coalesce(is_active, true)
    limit 1
  ), false)
$$;


-- 5) Je to sauna admin (nebo rovnou admin)? --------------------------------
create or replace function public.is_sauna_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select is_admin or coalesce(is_sauna_admin, false) from public.members
    where auth_id = auth.uid() and coalesce(is_active, true)
    limit 1
  ), false)
$$;


-- 6) Naparovani pri prvnim prihlaseni --------------------------------------
-- Najde clena podle e-mailu z overeneho prihlaseni a pripoji ho k uctu.
-- Kdo v seznamu clenu neni, nedostane nic.
create or replace function public.link_my_account()
returns text
language plpgsql security definer set search_path = public
as $$
declare
  mid  text;
  mail text;
begin
  -- uz naparovany?
  select id into mid from public.members where auth_id = auth.uid() limit 1;
  if mid is not null then
    return mid;
  end if;

  mail := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  if mail = '' then
    return null;
  end if;

  select id into mid from public.members
  where lower(trim(email)) = mail and auth_id is null
  limit 1;

  if mid is null then
    return null;   -- e-mail neni v seznamu clenu = zadny pristup
  end if;

  update public.members set auth_id = auth.uid() where id = mid;
  return mid;
end
$$;


-- 7) Kdo smi funkce volat: jen prihlaseni ----------------------------------
revoke execute on function public.current_member_id() from public, anon;
revoke execute on function public.is_club_member()    from public, anon;
revoke execute on function public.is_club_admin()     from public, anon;
revoke execute on function public.is_sauna_admin()    from public, anon;
revoke execute on function public.link_my_account()   from public, anon;

grant execute on function public.current_member_id() to authenticated;
grant execute on function public.is_club_member()    to authenticated;
grant execute on function public.is_club_admin()     to authenticated;
grant execute on function public.is_sauna_admin()    to authenticated;
grant execute on function public.link_my_account()   to authenticated;


-- 8) KONTROLA -----------------------------------------------------------
-- Supabase zobrazi vysledek posledniho prikazu, proto je vse v jedne tabulce.
-- Vysledek posli zpatky, at vim, s kym pocitat.
select 1 as poradi, 'clenu celkem' as ukazatel, count(*)::text as hodnota
from public.members
union all
select 2, 'bez e-mailu (neprihlasi se)', count(*)::text
from public.members where email is null or trim(email) = ''
union all
select 3, 'jiz naparovanych', count(*)::text
from public.members where auth_id is not null
union all
select 4, 'DUPLICITA: ' || e.email, e.pocet::text
from (
  select lower(trim(email)) as email, count(*) as pocet
  from public.members
  where email is not null and trim(email) <> ''
  group by 1 having count(*) > 1
) e
union all
select 5, 'BEZ E-MAILU: ' || name, id
from public.members
where email is null or trim(email) = ''
order by 1, 2;
