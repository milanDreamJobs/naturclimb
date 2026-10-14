-- ============================================================
-- NaturClimb - KROK 7: ohlasene platby a rocni prispevky
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 6.
--
-- Co to prinasi:
--   1) Clen muze ohlasit platbu na oddilovy ucet. Castka se NEPRIPISE
--      hned - ceka na potvrzeni admina, ktery ji odklikne podle vypisu.
--      Diky tomu si nikdo nemuze sam navysit konto.
--   2) Rocni prispevky: dve sazby (plna a zvyhodnena), clovek si pri
--      platbe vybere svou.
--
-- Nic nemaze.
-- ============================================================


-- 1) Sazby prispevku v nastaveni klubu -------------------------------------
alter table public.settings
  add column if not exists membership_fee_full integer not null default 800;
alter table public.settings
  add column if not exists membership_fee_reduced integer not null default 500;


-- 2) Tabulka ohlasenych plateb ---------------------------------------------
create table if not exists public.payment_claims (
  id          text primary key,
  member_id   text not null references public.members(id) on delete cascade,
  amount      integer not null check (amount > 0 and amount <= 100000),
  kind        text not null default 'topup',       -- 'topup' | 'membership'
  fee_type    text,                                -- 'full' | 'reduced' (jen u prispevku)
  year        integer,                             -- rok prispevku
  status      text not null default 'pending',     -- 'pending' | 'confirmed' | 'rejected'
  note        text,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  text
);

create index if not exists payment_claims_member_idx on public.payment_claims(member_id);
create index if not exists payment_claims_status_idx on public.payment_claims(status);

alter table public.payment_claims enable row level security;

-- Clen vidi sve ohlasene platby, admin vsechny.
drop policy if exists auth_claims_select on public.payment_claims;
create policy auth_claims_select on public.payment_claims
  for select to authenticated
  using (public.is_club_admin() or member_id = public.current_member_id());

-- Zapisuje se vyhradne pres funkce nize; admin smi i primo.
drop policy if exists auth_claims_admin on public.payment_claims;
create policy auth_claims_admin on public.payment_claims
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());

grant select on public.payment_claims to authenticated;


-- 3) Clen ohlasi platbu ----------------------------------------------------
create or replace function public.claim_payment(
  p_amount   integer,
  p_kind     text default 'topup',
  p_fee_type text default null
)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  mid     text;
  new_id  text;
  rok     integer := extract(year from now() at time zone 'Europe/Prague')::int;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount > 100000 then
    raise exception 'Neplatna castka';
  end if;

  if p_kind not in ('topup', 'membership') then
    raise exception 'Neplatny typ platby';
  end if;

  if p_kind = 'membership' and (p_fee_type is null or p_fee_type not in ('full','reduced')) then
    raise exception 'U prispevku vyber sazbu';
  end if;

  -- jedno cekajici ohlaseni na cloveka staci; starsi zrusime
  update public.payment_claims
     set status = 'rejected', decided_at = now(), decided_by = mid, note = 'nahrazeno novym ohlasenim'
   where member_id = mid and status = 'pending';

  new_id := 'pc_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.payment_claims (id, member_id, amount, kind, fee_type, year)
  values (new_id, mid, p_amount, p_kind,
          case when p_kind = 'membership' then p_fee_type else null end,
          case when p_kind = 'membership' then rok else null end);

  return new_id;
end
$$;


-- 4) Clen zrusi sve cekajici ohlaseni --------------------------------------
create or replace function public.cancel_my_claim(p_claim_id text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  mid text;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  update public.payment_claims
     set status = 'rejected', decided_at = now(), decided_by = mid, note = 'zruseno clenem'
   where id = p_claim_id and member_id = mid and status = 'pending';
end
$$;


-- 5) Admin potvrdi platbu - teprve ted se pripise na konto -----------------
create or replace function public.confirm_payment_claim(p_claim_id text)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  c       public.payment_claims%rowtype;
  mid     text;
  tx_id   text;
  popis   text;
  novy    integer;
begin
  if not public.is_club_admin() then
    raise exception 'Potvrzovat platby muze jen admin';
  end if;

  mid := public.current_member_id();

  select * into c from public.payment_claims where id = p_claim_id;
  if not found then
    raise exception 'Ohlasena platba neexistuje';
  end if;
  if c.status <> 'pending' then
    raise exception 'Tahle platba uz je vyrizena';
  end if;

  popis := case
    when c.kind = 'membership' and c.fee_type = 'reduced'
      then 'Clensky prispevek ' || c.year || ' (zvyhodneny)'
    when c.kind = 'membership'
      then 'Clensky prispevek ' || c.year
    else 'Platba na ucet'
  end;

  tx_id := 'tx_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.transactions (id, member_id, amount, type, description, created_by, created_at)
  values (tx_id, c.member_id, c.amount,
          case when c.kind = 'membership' then 'membership_fee' else 'bank_deposit' end,
          popis, mid, now());

  update public.payment_claims
     set status = 'confirmed', decided_at = now(), decided_by = mid
   where id = p_claim_id;

  select coalesce(sum(amount), 0) into novy
    from public.transactions where member_id = c.member_id;
  update public.members set balance = novy where id = c.member_id;

  return novy;
end
$$;


-- 6) Admin zamitne ---------------------------------------------------------
create or replace function public.reject_payment_claim(p_claim_id text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_club_admin() then
    raise exception 'Zamitat platby muze jen admin';
  end if;

  update public.payment_claims
     set status = 'rejected', decided_at = now(),
         decided_by = public.current_member_id(),
         note = coalesce(p_note, 'zamitnuto adminem')
   where id = p_claim_id and status = 'pending';
end
$$;


-- 7) Opravneni -------------------------------------------------------------
revoke execute on function public.claim_payment(integer, text, text) from public, anon;
revoke execute on function public.cancel_my_claim(text)              from public, anon;
revoke execute on function public.confirm_payment_claim(text)        from public, anon;
revoke execute on function public.reject_payment_claim(text, text)   from public, anon;

grant execute on function public.claim_payment(integer, text, text) to authenticated;
grant execute on function public.cancel_my_claim(text)              to authenticated;
grant execute on function public.confirm_payment_claim(text)        to authenticated;
grant execute on function public.reject_payment_claim(text, text)   to authenticated;


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'tabulka payment_claims' as co,
       coalesce((select 'existuje' from information_schema.tables
         where table_schema='public' and table_name='payment_claims'), 'CHYBI') as stav
union all
select 2, 'sazba plna / zvyhodnena',
       coalesce((select membership_fee_full || ' / ' || membership_fee_reduced
                 from public.settings where id = 1), 'nenastaveno')
union all
select 3, 'funkce pro platby (ceka se 4)',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname='public'
          and p.proname in ('claim_payment','cancel_my_claim','confirm_payment_claim','reject_payment_claim'))
order by 1;
