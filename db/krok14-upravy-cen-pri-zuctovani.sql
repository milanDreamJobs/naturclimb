-- ============================================================
-- NaturClimb - KROK 14: uprava cen pri zuctovani akce
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 13.
--
-- Co to prinasi:
--   1) Pri zuctovani akce muze admin jeste doladit ceny (ubytovani,
--      zvyhodnene ubytovani a vsech sest polozek).
--   2) Kdo jeste nebyl vyuctovany, dostane rovnou novou cenu.
--      Kdo se vyuctoval sam, dostane rozdil - na konto se mu pripise
--      nebo z nej odejde, podle toho, kterym smerem se cena hnula.
--   3) Cele zuctovani je JEDNA operace. Dosud to prohlizec projizdel
--      cloveka po cloveku a pri zavreni notebooku zustala pulka lidi
--      nezuctovana. Ted bud probehne vsechno, nebo nic.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================


-- 1) Zuctovani akce s moznosti upravit ceny --------------------------------
-- p_item_prices = pole sesti cen (polozka 1..6).
-- p_dry_run = true jen spocita dopad a nic nezapise (pouziva se pro nahled).
create or replace function public.settle_event(
  p_event_id          text,
  p_price_acc         integer,
  p_price_acc_reduced integer,
  p_item_prices       integer[],
  p_dry_run           boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  mid        text;
  e          public.events%rowtype;
  r          record;
  ceny       integer[] := array[0,0,0,0,0,0];
  i          integer;
  vych_noci  integer;
  noci       integer;
  nova       integer;
  rozdil     integer;
  tx_id      text;
  popis      text;
  zmena_cen  text;
  n_strzeno  integer := 0;
  s_strzeno  integer := 0;
  n_oprav    integer := 0;
  s_oprav    integer := 0;
  dotceni    text[]  := array[]::text[];
  novy       integer;
begin
  if not public.is_club_admin() then
    raise exception 'Zuctovat akci muze jen admin';
  end if;

  select * into e from public.events where id = p_event_id;
  if not found then
    raise exception 'Akce neexistuje';
  end if;
  if e.status = 'settled' then
    raise exception 'Akce uz je zuctovana';
  end if;

  -- ceny: cele cislo 0 az 100000, nic jineho
  if p_price_acc is null or p_price_acc < 0 or p_price_acc > 100000 then
    raise exception 'Neplatna cena ubytovani';
  end if;
  if p_price_acc_reduced is null or p_price_acc_reduced < 0 or p_price_acc_reduced > 100000 then
    raise exception 'Neplatna zvyhodnena cena ubytovani';
  end if;
  for i in 1..6 loop
    ceny[i] := coalesce(p_item_prices[i], 0);
    if ceny[i] < 0 or ceny[i] > 100000 then
      raise exception 'Neplatna cena polozky %', i;
    end if;
  end loop;

  -- popis zmeny cen - at je v historii konta videt duvod
  zmena_cen := nullif(array_to_string(array_remove(array[
    case when p_price_acc <> coalesce(e.price_accommodation, 0)
         then 'ubytování ' || coalesce(e.price_accommodation, 0) || ' → ' || p_price_acc || ' Kč' end,
    case when p_price_acc_reduced <> coalesce(e.price_accommodation_reduced, 0)
         then 'zvýhodněné ubytování ' || coalesce(e.price_accommodation_reduced, 0) || ' → ' || p_price_acc_reduced || ' Kč' end,
    case when ceny[1] <> coalesce(e.beer1_price, 0) and coalesce(e.beer1_name, '') <> ''
         then e.beer1_name || ' ' || coalesce(e.beer1_price, 0) || ' → ' || ceny[1] || ' Kč' end,
    case when ceny[2] <> coalesce(e.beer2_price, 0) and coalesce(e.beer2_name, '') <> ''
         then e.beer2_name || ' ' || coalesce(e.beer2_price, 0) || ' → ' || ceny[2] || ' Kč' end,
    case when ceny[3] <> coalesce(e.item3_price, 0) and coalesce(e.item3_name, '') <> ''
         then e.item3_name || ' ' || coalesce(e.item3_price, 0) || ' → ' || ceny[3] || ' Kč' end,
    case when ceny[4] <> coalesce(e.item4_price, 0) and coalesce(e.item4_name, '') <> ''
         then e.item4_name || ' ' || coalesce(e.item4_price, 0) || ' → ' || ceny[4] || ' Kč' end,
    case when ceny[5] <> coalesce(e.item5_price, 0) and coalesce(e.item5_name, '') <> ''
         then e.item5_name || ' ' || coalesce(e.item5_price, 0) || ' → ' || ceny[5] || ' Kč' end,
    case when ceny[6] <> coalesce(e.item6_price, 0) and coalesce(e.item6_name, '') <> ''
         then e.item6_name || ' ' || coalesce(e.item6_price, 0) || ' → ' || ceny[6] || ' Kč' end
  ], null), ', '), '');

  mid := public.current_member_id();
  vych_noci := greatest(1, ceil(extract(epoch from (e.end_datetime - e.start_datetime)) / 86400)::int);

  -- a) prepocet pro kazdeho prihlaseneho
  for r in
    select * from public.event_registrations where event_id = p_event_id order by id
  loop
    noci := coalesce(r.nights, vych_noci);
    nova := noci * p_price_acc
          + coalesce(r.nights_reduced, 0) * p_price_acc_reduced
          + coalesce(r.beer1_count, 0) * ceny[1]
          + coalesce(r.beer2_count, 0) * ceny[2]
          + coalesce(r.item3_count, 0) * ceny[3]
          + coalesce(r.item4_count, 0) * ceny[4]
          + coalesce(r.item5_count, 0) * ceny[5]
          + coalesce(r.item6_count, 0) * ceny[6];

    if r.settled_at is null then
      -- jeste nevyuctovany: strhneme rovnou novou cenu
      if nova > 0 then
        n_strzeno := n_strzeno + 1;
        s_strzeno := s_strzeno + nova;
        dotceni := dotceni || r.member_id;
        if not p_dry_run then
          popis := 'Akce: ' || e.name;
          tx_id := 'tx_' || replace(gen_random_uuid()::text, '-', '');
          insert into public.transactions
            (id, member_id, amount, type, description, created_by, created_at)
          values (tx_id, r.member_id, -nova, 'event_charge', popis, mid, now());
        end if;
      end if;
    else
      -- vyuctoval se sam: dorovname rozdil obema smery
      rozdil := coalesce(r.settled_amount, 0) - nova;
      if rozdil <> 0 then
        n_oprav := n_oprav + 1;
        s_oprav := s_oprav + rozdil;
        dotceni := dotceni || r.member_id;
        if not p_dry_run then
          popis := case when rozdil > 0 then 'Sleva z akce: ' else 'Doúčtování akce: ' end
                || e.name
                || case when zmena_cen is null then '' else ' (' || zmena_cen || ')' end;
          tx_id := 'tx_' || replace(gen_random_uuid()::text, '-', '');
          insert into public.transactions
            (id, member_id, amount, type, description, created_by, created_at)
          values (tx_id, r.member_id, rozdil, 'event_adjustment', popis, mid, now());

          update public.event_registrations
             set settled_amount = nova, updated_at = now()
           where id = r.id;
        end if;
      end if;
    end if;
  end loop;

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'charged_count', n_strzeno, 'charged_sum', s_strzeno,
      'adjusted_count', n_oprav, 'adjusted_sum', s_oprav,
      'price_change', coalesce(zmena_cen, '')
    );
  end if;

  -- b) nove ceny plati u akce a akce je zuctovana
  update public.events
     set price_accommodation         = p_price_acc,
         price_accommodation_reduced = p_price_acc_reduced,
         beer1_price = ceny[1], beer2_price = ceny[2],
         item3_price = ceny[3], item4_price = ceny[4],
         item5_price = ceny[5], item6_price = ceny[6],
         status = 'settled'
   where id = p_event_id;

  -- c) prepocet zustatku dotcenych lidi (nikdy se nezapisuje "nejake cislo")
  for i in 1..coalesce(array_length(dotceni, 1), 0) loop
    select coalesce(sum(amount), 0) into novy
      from public.transactions where member_id = dotceni[i];
    update public.members set balance = novy where id = dotceni[i];
    update public.transactions
       set balance_after = novy
     where member_id = dotceni[i] and balance_after is null;
  end loop;

  return jsonb_build_object(
    'dry_run', false,
    'charged_count', n_strzeno, 'charged_sum', s_strzeno,
    'adjusted_count', n_oprav, 'adjusted_sum', s_oprav,
    'price_change', coalesce(zmena_cen, '')
  );
end
$$;

revoke execute on function public.settle_event(text, integer, integer, integer[], boolean) from public, anon;
grant  execute on function public.settle_event(text, integer, integer, integer[], boolean) to authenticated;


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'funkce settle_event' as co,
       coalesce((select 'existuje' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname='public' and p.proname='settle_event' limit 1), 'CHYBI') as hodnota
union all
select 2, 'nezuctovanych akci',
       (select count(*)::text from public.events where status <> 'settled')
order by 1;
