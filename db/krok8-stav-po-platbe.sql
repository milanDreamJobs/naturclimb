-- ============================================================
-- NaturClimb - KROK 8: doplneni "stavu po" u plateb
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spusteny krok 7.
--
-- Proc: funkce confirm_payment_claim zapisovala transakci bez pole
-- balance_after. Detail takoveho clena se pak v adminu neotevrel.
-- Tenhle skript (1) opravi funkci do budoucna a (2) dopocita
-- chybejici hodnoty u existujicich transakci.
-- ============================================================


-- 1) Funkce nove doplni i "stav po" -----------------------------------------
create or replace function public.confirm_payment_claim(p_claim_id text)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  c      public.payment_claims%rowtype;
  mid    text;
  tx_id  text;
  popis  text;
  novy   integer;
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

  -- zustatek po teto platbe
  select coalesce(sum(amount), 0) + c.amount into novy
    from public.transactions where member_id = c.member_id;

  tx_id := 'tx_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.transactions
    (id, member_id, amount, type, description, balance_after, created_by, created_at)
  values
    (tx_id, c.member_id, c.amount,
     case when c.kind = 'membership' then 'membership_fee' else 'bank_deposit' end,
     popis, novy, mid, now());

  update public.payment_claims
     set status = 'confirmed', decided_at = now(), decided_by = mid
   where id = p_claim_id;

  update public.members set balance = novy where id = c.member_id;

  return novy;
end
$$;

revoke execute on function public.confirm_payment_claim(text) from public, anon;
grant  execute on function public.confirm_payment_claim(text) to authenticated;


-- 2) Dopocitat "stav po" tam, kde chybi ------------------------------------
with serazene as (
  select id,
         sum(amount) over (
           partition by member_id
           order by created_at, id
           rows between unbounded preceding and current row
         ) as bezici_soucet
  from public.transactions
)
update public.transactions t
   set balance_after = s.bezici_soucet
  from serazene s
 where s.id = t.id
   and t.balance_after is null;


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'transakce bez stavu po (ma byt 0)' as co,
       count(*)::text as hodnota
from public.transactions where balance_after is null
union all
select 2, 'transakci celkem', count(*)::text from public.transactions
order by 1;
