-- ============================================================
-- BarberHub — migração 01
-- Intervalo entre os horários oferecidos ao cliente.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

alter table estabelecimentos
  add column if not exists intervalo_min smallint not null default 30
  check (intervalo_min in (10, 15, 20, 30, 60));

comment on column estabelecimentos.intervalo_min is
  'De quantos em quantos minutos os horários são oferecidos ao cliente.';
