-- ============================================================
-- NaturClimb - KROK 4: nova pravidla pristupu (RLS)
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: uz je spusteny krok 3 (sloupec auth_id a funkce).
--
-- DULEZITE: tato pravidla se PRIDAVAJI vedle stavajicich pravidel
-- s club tokenem. Nic se timto krokem nerozbije - aplikace bezi dal
-- presne jako ted. Stara pravidla smazeme az uplne nakonec (krok 6),
-- kdyz bude nove prihlasovani otestovane.
-- ============================================================


-- Pomocna funkce: e-mail prihlaseneho (mapa vede autory pres e-mail)
create or replace function public.current_member_email()
returns text
language sql stable security definer set search_path = public
as $$
  select lower(trim(coalesce(auth.jwt() ->> 'email', '')))
$$;

revoke execute on function public.current_member_email() from public, anon;
grant  execute on function public.current_member_email() to authenticated;


-- ============================================================
-- CLENOVE
-- ============================================================
-- Cteni: kazdy prihlaseny clen (potrebuje videt, kdo jde na trenink).
drop policy if exists auth_members_select on public.members;
create policy auth_members_select on public.members
  for select to authenticated
  using (public.is_club_member());

-- Zapis: jen admin. Bezny clen si tak nemuze zvysit konto ani si dat admina.
drop policy if exists auth_members_admin on public.members;
create policy auth_members_admin on public.members
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());


-- ============================================================
-- NASTAVENI KLUBU
-- ============================================================
drop policy if exists auth_settings_select on public.settings;
create policy auth_settings_select on public.settings
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_settings_admin on public.settings;
create policy auth_settings_admin on public.settings
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());


-- ============================================================
-- TRENINKY
-- ============================================================
-- Cteni: vsichni clenove.
drop policy if exists auth_trainings_select on public.trainings;
create policy auth_trainings_select on public.trainings
  for select to authenticated
  using (public.is_club_member());

-- Zakladat, menit a mazat: admin.
drop policy if exists auth_trainings_admin on public.trainings;
create policy auth_trainings_admin on public.trainings
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());

-- Sauna admin: smi menit jen treninky sauny (zuctovani).
drop policy if exists auth_trainings_sauna on public.trainings;
create policy auth_trainings_sauna on public.trainings
  for update to authenticated
  using (public.is_sauna_admin() and venue is not null and lower(venue) like '%sauna%')
  with check (public.is_sauna_admin() and venue is not null and lower(venue) like '%sauna%');

-- Prihlasovani clenu na treninky NENI primy zapis do tabulky -
-- resi ho chranene funkce, ktere prijdou v kroku 5.


-- ============================================================
-- TRANSAKCE (pohyby na kontech)
-- ============================================================
-- Clen vidi jen sve vlastni pohyby, admin vsechny.
drop policy if exists auth_tx_select on public.transactions;
create policy auth_tx_select on public.transactions
  for select to authenticated
  using (public.is_club_admin() or member_id = public.current_member_id());

-- Zapisovat smi admin; sauna admin kvuli zuctovani sauny.
drop policy if exists auth_tx_write on public.transactions;
create policy auth_tx_write on public.transactions
  for all to authenticated
  using (public.is_sauna_admin())
  with check (public.is_sauna_admin());


-- ============================================================
-- AKCE
-- ============================================================
drop policy if exists auth_events_select on public.events;
create policy auth_events_select on public.events
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_events_admin on public.events;
create policy auth_events_admin on public.events
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());


-- ============================================================
-- PRIHLASKY NA AKCE
-- ============================================================
-- Vsichni clenove vidi, kdo jede. Menit smi kazdy jen svou prihlasku.
drop policy if exists auth_evreg_select on public.event_registrations;
create policy auth_evreg_select on public.event_registrations
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_evreg_own on public.event_registrations;
create policy auth_evreg_own on public.event_registrations
  for all to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists auth_evreg_admin on public.event_registrations;
create policy auth_evreg_admin on public.event_registrations
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());


-- ============================================================
-- SPOLUJIZDY
-- ============================================================
-- Vsichni clenove vidi nabidky. Menit smi jen ridic svou vlastni.
drop policy if exists auth_rides_select on public.event_rides;
create policy auth_rides_select on public.event_rides
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_rides_own on public.event_rides;
create policy auth_rides_own on public.event_rides
  for all to authenticated
  using (driver_id = public.current_member_id())
  with check (driver_id = public.current_member_id());

drop policy if exists auth_rides_admin on public.event_rides;
create policy auth_rides_admin on public.event_rides
  for all to authenticated
  using (public.is_club_admin())
  with check (public.is_club_admin());

-- Rezervace mista v cizim aute resi chranena funkce z kroku 5.


-- ============================================================
-- MAPA (body, fotky, zajem) - autor je veden pres e-mail
-- ============================================================
drop policy if exists auth_map_points_select on public.map_points;
create policy auth_map_points_select on public.map_points
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_map_points_insert on public.map_points;
create policy auth_map_points_insert on public.map_points
  for insert to authenticated
  with check (public.is_club_member());

drop policy if exists auth_map_points_own on public.map_points;
create policy auth_map_points_own on public.map_points
  for all to authenticated
  using (public.is_club_admin()
         or lower(trim(coalesce(member_email, ''))) = public.current_member_email())
  with check (public.is_club_admin()
         or lower(trim(coalesce(member_email, ''))) = public.current_member_email());


drop policy if exists auth_map_photos_select on public.map_point_photos;
create policy auth_map_photos_select on public.map_point_photos
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_map_photos_insert on public.map_point_photos;
create policy auth_map_photos_insert on public.map_point_photos
  for insert to authenticated
  with check (public.is_club_member());

drop policy if exists auth_map_photos_own on public.map_point_photos;
create policy auth_map_photos_own on public.map_point_photos
  for all to authenticated
  using (public.is_club_admin()
         or lower(trim(coalesce(uploaded_by, ''))) = public.current_member_email())
  with check (public.is_club_admin()
         or lower(trim(coalesce(uploaded_by, ''))) = public.current_member_email());


drop policy if exists auth_map_interest_select on public.map_point_interest;
create policy auth_map_interest_select on public.map_point_interest
  for select to authenticated
  using (public.is_club_member());

drop policy if exists auth_map_interest_own on public.map_point_interest;
create policy auth_map_interest_own on public.map_point_interest
  for all to authenticated
  using (public.is_club_admin()
         or lower(trim(coalesce(member_email, ''))) = public.current_member_email())
  with check (public.is_club_admin()
         or lower(trim(coalesce(member_email, ''))) = public.current_member_email());


-- ============================================================
-- KONTROLA
-- ============================================================
-- Kazda tabulka ma mit vedle stare politiky (club_*) nove (auth_*).
select
  tablename                                                  as tabulka,
  count(*) filter (where policyname like 'auth[_]%')::text   as nova_pravidla,
  count(*) filter (where policyname not like 'auth[_]%')::text as stara_pravidla
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;
