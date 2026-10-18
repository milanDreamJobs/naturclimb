-- ============================================================
-- NaturClimb - KROK 10: pojistka proti dvojim prihlaskam a odvozum
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit cele -> Run
-- Predpoklad: spustene kroky 3 az 9.
--
-- Proc: aplikace sice vzdy hleda existujici prihlasku, ale kdyz se
-- zapis nepovedl a clovek to zkousel znovu z jineho zarizeni,
-- teoreticky mohly vzniknout dve prihlasky na jednoho cloveka.
-- Tahle pojistka to zaridi primo v databazi.
--
-- Pozn.: dnes zadne duplicity v datech nejsou (overeno 18. 10. 2026).
-- ============================================================


-- 1) Kdyby presto nejake duplicity byly, necháme nejnovejsi ----------------
with poradi as (
  select id,
         row_number() over (
           partition by event_id, member_id
           order by coalesce(updated_at, created_at) desc, created_at desc
         ) as poradi
  from public.event_registrations
)
delete from public.event_registrations r
 using poradi p
 where p.id = r.id and p.poradi > 1;

with poradi as (
  select id,
         row_number() over (
           partition by event_id, driver_id, direction
           order by created_at desc
         ) as poradi
  from public.event_rides
)
delete from public.event_rides r
 using poradi p
 where p.id = r.id and p.poradi > 1;


-- 2) Jeden clovek = jedna prihlaska na akci -------------------------------
create unique index if not exists event_registrations_jedna_na_cloveka
  on public.event_registrations (event_id, member_id);

-- Jeden ridic = jedna nabidka na smer
create unique index if not exists event_rides_jedna_na_ridice
  on public.event_rides (event_id, driver_id, direction);


-- ------------------------------------------------------------
-- KONTROLA
-- ------------------------------------------------------------
select 1 as poradi, 'duplicitni prihlasky (ma byt 0)' as co,
       (select count(*)::text from (
          select 1 from public.event_registrations
          group by event_id, member_id having count(*) > 1) x) as hodnota
union all
select 2, 'prihlasek celkem', (select count(*)::text from public.event_registrations)
union all
select 3, 'nabidek odvozu celkem', (select count(*)::text from public.event_rides)
order by 1;
