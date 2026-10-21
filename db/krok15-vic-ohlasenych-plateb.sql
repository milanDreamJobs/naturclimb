-- ============================================================
-- NaturClimb - KROK 15: vic ohlasenych plateb vedle sebe
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 14.
--
-- Proc: dosud platilo "jedno cekajici ohlaseni na cloveka" - kdyz nekdo
-- ohlasil prispevek a pak jeste dobiti konta, prvni ohlaseni se tise
-- zrusilo. Nove muzou cekat vedle sebe (nejvyse pet), jen prispevek
-- jde ohlasit jednou za sezonu.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================

create or replace function public.claim_payment2(
  p_fee_type     text    default null,   -- 'full' | 'reduced' | null (= bez prispevku)
  p_topup_amount integer default 0,
  p_keep_pending boolean default false   -- true = nechat starsi ohlaseni byt
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
  ceka    integer;
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

    -- prispevek jde ohlasit jen jednou, at ho admin nepotvrdi dvakrat
    if p_keep_pending and exists (
      select 1 from public.payment_claims
       where member_id = mid and status = 'pending' and coalesce(fee_amount, 0) > 0
    ) then
      raise exception 'Prispevek uz mas ohlaseny a ceka na potvrzeni';
    end if;
  end if;

  celkem := fee + topup;
  if celkem <= 0 then
    raise exception 'Vyber, co platis';
  end if;
  if celkem > 100000 then
    raise exception 'Tak velkou castku radsi dohodni s adminem osobne';
  end if;

  if p_keep_pending then
    select count(*) into ceka from public.payment_claims
     where member_id = mid and status = 'pending';
    if ceka >= 5 then
      raise exception 'Mas uz peti cekajicich plateb - pockej, az je admin potvrdi';
    end if;
  else
    -- stare chovani: nove ohlaseni nahradi predchozi
    update public.payment_claims
       set status = 'rejected', decided_at = now(), decided_by = mid,
           note = 'nahrazeno novym ohlasenim'
     where member_id = mid and status = 'pending';
  end if;

  druh := case when fee > 0 and topup > 0 then 'both'
               when fee > 0               then 'membership'
               else                            'topup' end;

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

revoke execute on function public.claim_payment2(text, integer, boolean) from public, anon;
grant  execute on function public.claim_payment2(text, integer, boolean) to authenticated;


-- Puvodni dvouparametrova podoba musi pryc, jinak by vedle sebe byly dve
-- funkce stejneho jmena a volani se dvema parametry by bylo nejednoznacne
-- (chyba "function is not unique"). Nova funkce ji plne nahradi - treti
-- parametr ma vychozi hodnotu, takze stara volani chodi dal.
drop function if exists public.claim_payment2(text, integer);


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'funkce claim_payment2 ma 3 parametry' as co,
       coalesce((select 'ano' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname='public' and p.proname='claim_payment2'
           and p.pronargs = 3 limit 1), 'CHYBI') as hodnota
union all
select 2, 'cekajicich plateb k potvrzeni',
       (select count(*)::text from public.payment_claims where status = 'pending')
order by 1;
