-- ============================================================
-- NaturClimb - KROK 11: clenske prispevky po sezonach
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 10.
--
-- Co to prinasi:
--   1) Sezona prispevku (1.9. - 31.8.), v nastaveni se da prepnout
--      na kalendarni rok (zacatek = mesic 1).
--   2) Tabulka membership_fees: zaplaceny prispevek je SKUTECNY zapis,
--      ne odhad z transakci. Jeden radek = clen x sezona.
--   3) Jedna ohlasena platba muze obsahovat prispevek A dobiti konta
--      zaroven (fee_amount + topup_amount = amount).
--   4) Prispevek se NEPRIPISUJE na konto. Na konto jde jen dobiti.
--   5) Admin muze prispevek zapsat rucne (hotovost) a vzit zpet.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================


-- 1) Zacatek sezony v nastaveni --------------------------------------------
alter table public.settings
  add column if not exists fee_season_start_month integer not null default 9;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'settings_season_month_ok') then
    alter table public.settings
      add constraint settings_season_month_ok
      check (fee_season_start_month between 1 and 12);
  end if;
end $$;


-- 2) Ktera sezona bezi dnes (vraci rok jejiho zacatku) ---------------------
-- Zari 2026 az srpen 2027 => 2026 (popisek "2026/27").
create or replace function public.current_fee_season()
returns integer
language sql stable security definer set search_path = public
as $$
  with t as (
    select (now() at time zone 'Europe/Prague')::date as d,
           coalesce((select fee_season_start_month from public.settings where id = 1), 9) as m
  )
  select case when extract(month from d)::int >= m
              then extract(year from d)::int
              else extract(year from d)::int - 1
         end
    from t;
$$;


-- 3) Tabulka zaplacenych prispevku -----------------------------------------
create table if not exists public.membership_fees (
  id          text primary key default ('mf_' || replace(gen_random_uuid()::text, '-', '')),
  member_id   text not null references public.members(id) on delete cascade,
  season_year integer not null,
  fee_type    text not null default 'full',
  amount      integer not null default 0 check (amount >= 0 and amount <= 100000),
  paid_at     timestamptz not null default now(),
  claim_id    text,
  created_by  text,
  note        text
);

create unique index if not exists membership_fees_one_per_season
  on public.membership_fees(member_id, season_year);
create index if not exists membership_fees_season_idx
  on public.membership_fees(season_year);

alter table public.membership_fees enable row level security;

-- Cteni: kdokoli z klubu (clen vidi svoje razitko, admin prehled vsech).
drop policy if exists auth_fees_select on public.membership_fees;
create policy auth_fees_select on public.membership_fees
  for select to authenticated
  using (public.is_club_member());

-- Zapis: jen admin (a funkce nize, ktere bezi jako security definer).
drop policy if exists auth_fees_admin on public.membership_fees;
create policy auth_fees_admin on public.membership_fees
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());

grant select on public.membership_fees to authenticated;


-- 4) Ohlasena platba se rozpadne na prispevek + dobiti ---------------------
alter table public.payment_claims
  add column if not exists fee_amount integer not null default 0;
alter table public.payment_claims
  add column if not exists topup_amount integer not null default 0;
alter table public.payment_claims
  add column if not exists season_year integer;

-- Dopocet u plateb, ktere vznikly pred timto krokem.
update public.payment_claims
   set fee_amount   = case when kind = 'membership' then amount else 0 end,
       topup_amount = case when kind = 'membership' then 0 else amount end,
       season_year  = case when kind = 'membership' then year else null end
 where fee_amount = 0 and topup_amount = 0;


-- 5) Clen ohlasi platbu - nove i obe polozky naraz -------------------------
-- Sazbu prispevku si funkce bere z nastaveni sama, klient ji neposila.
create or replace function public.claim_payment2(
  p_fee_type     text    default null,   -- 'full' | 'reduced' | null (= bez prispevku)
  p_topup_amount integer default 0
)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  mid     text;
  new_id  text;
  sezona  integer := public.current_fee_season();
  fee     integer := 0;
  topup   integer := greatest(coalesce(p_topup_amount, 0), 0);
  celkem  integer;
  druh    text;
begin
  mid := public.current_member_id();
  if mid is null then
    raise exception 'Nejsi prihlaseny clen klubu';
  end if;

  if p_fee_type is not null then
    if p_fee_type not in ('full', 'reduced') then
      raise exception 'Neplatna sazba prispevku';
    end if;

    select case when p_fee_type = 'reduced'
                then coalesce(membership_fee_reduced, 500)
                else coalesce(membership_fee_full, 800) end
      into fee
      from public.settings where id = 1;

    if fee is null or fee <= 0 then
      raise exception 'Admin jeste nenastavil sazby prispevku';
    end if;

    if exists (select 1 from public.membership_fees
                where member_id = mid and season_year = sezona) then
      raise exception 'Prispevek na tuhle sezonu uz mas zaplaceny';
    end if;
  end if;

  celkem := fee + topup;
  if celkem <= 0 then
    raise exception 'Vyber, co platis';
  end if;
  if celkem > 100000 then
    raise exception 'Tak velkou castku radsi dohodni s adminem osobne';
  end if;

  druh := case when fee > 0 and topup > 0 then 'both'
               when fee > 0               then 'membership'
               else                            'topup' end;

  -- jedno cekajici ohlaseni na cloveka staci; starsi zrusime
  update public.payment_claims
     set status = 'rejected', decided_at = now(), decided_by = mid,
         note = 'nahrazeno novym ohlasenim'
   where member_id = mid and status = 'pending';

  new_id := 'pc_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.payment_claims
    (id, member_id, amount, kind, fee_type, year, fee_amount, topup_amount, season_year)
  values
    (new_id, mid, celkem, druh,
     case when fee > 0 then p_fee_type else null end,
     case when fee > 0 then sezona else null end,
     fee, topup,
     case when fee > 0 then sezona else null end);

  return new_id;
end
$$;


-- 6) Stara funkce claim_payment zustava funkcni ----------------------------
-- (kdyby bezela starsi verze appky z cache prohlizece)
create or replace function public.claim_payment(
  p_amount   integer,
  p_kind     text default 'topup',
  p_fee_type text default null
)
returns text
language plpgsql security definer set search_path = public
as $$
begin
  if p_kind = 'membership' then
    return public.claim_payment2(p_fee_type, 0);
  end if;
  return public.claim_payment2(null, p_amount);
end
$$;


-- 7) Admin potvrdi platbu --------------------------------------------------
-- Dobiti jde na konto jako transakce. Prispevek na konto NEJDE - zapise se
-- do membership_fees a jen rozsviti razitko.
create or replace function public.confirm_payment_claim(p_claim_id text)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  c       public.payment_claims%rowtype;
  mid     text;
  tx_id   text;
  novy    integer;
  fee     integer;
  topup   integer;
  sezona  integer;
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

  fee   := coalesce(c.fee_amount, 0);
  topup := coalesce(c.topup_amount, 0);

  -- platba ohlasena starsi verzi appky: rozdelime podle kind
  if fee = 0 and topup = 0 then
    if c.kind = 'membership' then fee := c.amount; else topup := c.amount; end if;
  end if;

  sezona := coalesce(c.season_year, c.year, public.current_fee_season());

  -- a) dobiti konta
  if topup > 0 then
    tx_id := 'tx_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.transactions
      (id, member_id, amount, type, description, created_by, created_at)
    values
      (tx_id, c.member_id, topup, 'bank_deposit', 'Platba na ucet', mid, now());
  end if;

  -- b) clensky prispevek - mimo konto
  if fee > 0 then
    insert into public.membership_fees
      (member_id, season_year, fee_type, amount, paid_at, claim_id, created_by)
    values
      (c.member_id, sezona, coalesce(c.fee_type, 'full'), fee, now(), c.id, mid)
    on conflict (member_id, season_year) do update
      set amount = excluded.amount,
          fee_type = excluded.fee_type,
          paid_at = excluded.paid_at,
          claim_id = excluded.claim_id,
          created_by = excluded.created_by;
  end if;

  update public.payment_claims
     set status = 'confirmed', decided_at = now(), decided_by = mid
   where id = p_claim_id;

  select coalesce(sum(amount), 0) into novy
    from public.transactions where member_id = c.member_id;
  update public.members set balance = novy where id = c.member_id;

  -- dopocet stavu po transakci (kvuli historii konta)
  if topup > 0 then
    update public.transactions set balance_after = novy where id = tx_id;
  end if;

  return novy;
end
$$;


-- 8) Admin zapise prispevek rucne (hotovost) -------------------------------
create or replace function public.set_membership_fee(
  p_member_id text,
  p_fee_type  text default 'full',
  p_season    integer default null,
  p_note      text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  sezona integer := coalesce(p_season, public.current_fee_season());
  castka integer;
begin
  if not public.is_club_admin() then
    raise exception 'Zapisovat prispevky muze jen admin';
  end if;

  if p_fee_type not in ('full', 'reduced') then
    raise exception 'Neplatna sazba prispevku';
  end if;

  select case when p_fee_type = 'reduced'
              then coalesce(membership_fee_reduced, 500)
              else coalesce(membership_fee_full, 800) end
    into castka
    from public.settings where id = 1;

  insert into public.membership_fees
    (member_id, season_year, fee_type, amount, paid_at, created_by, note)
  values
    (p_member_id, sezona, p_fee_type, coalesce(castka, 0), now(),
     public.current_member_id(), coalesce(p_note, 'zapsano adminem'))
  on conflict (member_id, season_year) do update
    set fee_type = excluded.fee_type,
        amount = excluded.amount,
        paid_at = excluded.paid_at,
        created_by = excluded.created_by,
        note = excluded.note;
end
$$;


-- 9) Admin vezme zapis zpet ------------------------------------------------
create or replace function public.unset_membership_fee(
  p_member_id text,
  p_season    integer default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_club_admin() then
    raise exception 'Mazat prispevky muze jen admin';
  end if;

  delete from public.membership_fees
   where member_id = p_member_id
     and season_year = coalesce(p_season, public.current_fee_season());
end
$$;


-- 10) Dohledani historie ---------------------------------------------------
-- a) z jiz potvrzenych prispevkovych ohlaseni
insert into public.membership_fees
  (member_id, season_year, fee_type, amount, paid_at, claim_id, created_by, note)
select c.member_id,
       coalesce(c.season_year, c.year, extract(year from c.created_at)::int),
       coalesce(c.fee_type, 'full'),
       case when coalesce(c.fee_amount,0) > 0 then c.fee_amount else c.amount end,
       coalesce(c.decided_at, c.created_at),
       c.id, c.decided_by, 'dohledano z ohlasene platby'
  from public.payment_claims c
 where c.status = 'confirmed'
   and (c.kind in ('membership', 'both') or coalesce(c.fee_amount, 0) > 0)
on conflict (member_id, season_year) do nothing;

-- b) ze starych transakci typu membership_fee (pokud nejake existuji)
insert into public.membership_fees
  (member_id, season_year, fee_type, amount, paid_at, created_by, note)
select t.member_id,
       case when extract(month from (t.created_at at time zone 'Europe/Prague'))::int
                 >= coalesce((select fee_season_start_month from public.settings where id = 1), 9)
            then extract(year from (t.created_at at time zone 'Europe/Prague'))::int
            else extract(year from (t.created_at at time zone 'Europe/Prague'))::int - 1
       end,
       'full', t.amount, t.created_at, t.created_by, 'dohledano ze stare transakce'
  from public.transactions t
 where t.type = 'membership_fee'
on conflict (member_id, season_year) do nothing;


-- 11) Kontrola -------------------------------------------------------------
select 'sezona ted: ' || public.current_fee_season()::text as kontrola
union all
select 'zaplacenych prispevku v teto sezone: ' || count(*)::text
  from public.membership_fees where season_year = public.current_fee_season()
union all
select 'clenu celkem: ' || count(*)::text from public.members where is_active is not false;
