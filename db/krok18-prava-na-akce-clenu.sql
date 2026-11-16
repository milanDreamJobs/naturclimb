-- ============================================================
-- NaturClimb - KROK 18: prava na akce, ktere vypise clen
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 17 (sloupce z kroku 17 si tenhle
-- krok pro jistotu prida sam, kdyby krok 17 nebezel).
--
-- Proc: krok 17 pridal sloupce pro akce navrzene clenem, ale prava
-- zustala puvodni - zapisovat do tabulky akci smel jen admin. Clen
-- tedy v appce dostal "Akci se nepodarilo ulozit". Tenhle krok prava
-- dorovna, aby to odpovidalo domluve:
--
--   * kazdy clen muze navrhnout akci (vznikne jako navrh)
--   * navrh vidi jen jeho autor a admini
--   * schvalit navrh muze jedine admin
--   * autor schvalene akce ji spravuje jako admin, ale JEN svoji:
--     upravit, pridat ucastnika, posunout lhutu, zuctovat
--   * zuctovanou akci uz nemeni nikdo
--
-- Hlidani nestoji jen na pravidlech pro cteni a zapis, ale i na
-- strazci (trigger) primo u tabulky - takze si nikdo nemuze svuj
-- navrh schvalit sam, ani kdyby posilal data mimo appku.
--
-- Nic nemaze. Spustit se to da i vickrat.
-- ============================================================


-- 1) Sloupce z kroku 17 (kdyby nebezel) -----------------------------------
alter table public.events
  add column if not exists created_by_member text references public.members(id);
alter table public.events
  add column if not exists is_draft boolean default false;


-- 2) Kdo je autor akce ----------------------------------------------------
create or replace function public.is_event_author(p_event_id text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.events
     where id = p_event_id
       and created_by_member is not null
       and created_by_member = public.current_member_id()
  );
$$;

-- Prava k ucastnikum, lhute a zuctovani ma autor az po schvaleni.
create or replace function public.is_event_author_approved(p_event_id text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.events
     where id = p_event_id
       and created_by_member is not null
       and created_by_member = public.current_member_id()
       and coalesce(is_draft, false) = false
  );
$$;


-- 3) Cteni akci: cizi navrhy nikdo nevidi ---------------------------------
drop policy if exists auth_events_select on public.events;
create policy auth_events_select on public.events
  for select to authenticated
  using (
    public.is_club_member()
    and (
      coalesce(is_draft, false) = false
      or public.is_club_admin()
      or created_by_member = public.current_member_id()
    )
  );


-- 4) Clen smi zalozit svuj navrh ------------------------------------------
drop policy if exists auth_events_author_insert on public.events;
create policy auth_events_author_insert on public.events
  for insert to authenticated
  with check (
    public.is_club_member()
    and created_by_member = public.current_member_id()
  );


-- 5) Autor smi upravovat svoji akci ---------------------------------------
drop policy if exists auth_events_author_update on public.events;
create policy auth_events_author_update on public.events
  for update to authenticated
  using (created_by_member = public.current_member_id())
  with check (created_by_member = public.current_member_id());


-- 6) Stahnout smi autor jen vlastni navrh ---------------------------------
drop policy if exists auth_events_author_delete on public.events;
create policy auth_events_author_delete on public.events
  for delete to authenticated
  using (
    created_by_member = public.current_member_id()
    and coalesce(is_draft, false) = true
  );


-- 7) Strazce u tabulky ----------------------------------------------------
-- Pravidla vyse rikaji, KDO smi sahnout na radek. Tohle hlida, CO smi
-- zmenit - aby si clen nemohl svuj navrh schvalit ani prepsat autora.
create or replace function public.events_hlidac()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_club_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Pozor: appka uklada pres upsert, takze i uprava existujici akce
    -- prijde nejdriv jako insert. Nova je jen akce, ktera jeste neni.
    if not exists (select 1 from public.events where id = new.id) then
      new.created_by_member := public.current_member_id();
      new.is_draft := true;                 -- navrh vzdy ceka na schvaleni
      new.status := 'open';
    end if;
    return new;
  end if;

  if old.created_by_member is distinct from new.created_by_member then
    raise exception 'Autora akce menit nelze';
  end if;
  if coalesce(old.is_draft, false) and not coalesce(new.is_draft, false) then
    raise exception 'Navrh akce schvaluje admin';
  end if;
  if old.status = 'settled' then
    raise exception 'Zuctovanou akci uz menit nelze';
  end if;
  if coalesce(new.is_draft, false) and new.status is distinct from 'open' then
    raise exception 'Navrh akce nejde zuctovat';
  end if;

  return new;
end
$$;

drop trigger if exists events_hlidac_trg on public.events;
create trigger events_hlidac_trg
  before insert or update on public.events
  for each row execute function public.events_hlidac();


-- 8) Ucastnici: autor schvalene akce s nimi smi hybat ---------------------
drop policy if exists auth_evreg_author on public.event_registrations;
create policy auth_evreg_author on public.event_registrations
  for all to authenticated
  using (public.is_event_author_approved(event_id))
  with check (public.is_event_author_approved(event_id));


-- 9) Lhuta na vyuctovani: nove i autor ------------------------------------
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
  -- Nove i autor schvalene akce - svoji akci spravuje jako admin.
  if not (public.is_club_admin() or public.is_event_author_approved(p_event_id)) then
    raise exception 'Menit lhutu muze jen admin nebo autor akce';
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


-- 10) Zuctovani akce: nove i autor ---------------------------------------
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
  -- Nove i autor schvalene akce.
  if not (public.is_club_admin() or public.is_event_author_approved(p_event_id)) then
    raise exception 'Zuctovat akci muze jen admin nebo autor akce';
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
select 1 as poradi, 'sloupce pro akce clenu' as co,
       (select count(*)::text || ' ze 2' from information_schema.columns
         where table_schema='public' and table_name='events'
           and column_name in ('created_by_member','is_draft')) as hodnota
union all
select 2, 'pravidel u tabulky akci (ceka se 6)',
       (select count(*)::text from pg_policies
         where schemaname='public' and tablename='events')
union all
select 3, 'strazce u tabulky akci',
       coalesce((select 'ano' from pg_trigger
                  where tgname='events_hlidac_trg' and not tgisinternal limit 1), 'CHYBI')
union all
select 4, 'navrhu cekajicich na schvaleni',
       (select count(*)::text from public.events where coalesce(is_draft,false))
order by 1;
