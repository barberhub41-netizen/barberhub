-- ============================================================
-- BarberHub — migração 03
-- Bloqueios: almoço, pausa, folga, férias e feriado.
-- São faixas em que o profissional não recebe agendamento,
-- mesmo estando dentro da jornada de trabalho.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

create table if not exists bloqueios (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  -- nulo = vale para toda a equipe (feriado, fechamento da loja)
  barbeiro_id         uuid references barbeiros(id) on delete cascade,
  motivo              text,

  -- modo semanal: repete toda semana (almoço, pausa)
  dia_semana          smallint check (dia_semana between 0 and 6),
  hora_inicio         time,
  hora_fim            time,

  -- modo pontual: uma data específica (folga, férias, feriado)
  inicio              timestamptz,
  fim                 timestamptz,

  criado_em           timestamptz not null default now(),

  -- ou é semanal, ou é pontual — nunca os dois
  constraint bloqueios_modo check (
    (dia_semana is not null and hora_inicio is not null and hora_fim is not null
      and hora_fim > hora_inicio and inicio is null and fim is null)
    or
    (inicio is not null and fim is not null and fim > inicio
      and dia_semana is null and hora_inicio is null and hora_fim is null)
  )
);

create index if not exists idx_bloqueios_estab on bloqueios (estabelecimento_id);
create index if not exists idx_bloqueios_barbeiro on bloqueios (barbeiro_id);

-- ------------------------------------------------------------
-- Permissões
-- Leitura pública: é o que impede o cliente de ver o horário
-- do almoço como se estivesse livre.
-- ------------------------------------------------------------
alter table bloqueios enable row level security;

drop policy if exists bloqueios_ler on bloqueios;
create policy bloqueios_ler on bloqueios for select to anon, authenticated
using (
  public.estab_disponivel(estabelecimento_id)
  or public.gerencio_estab(estabelecimento_id)
  or public.sou_barbeiro(barbeiro_id)
);

drop policy if exists bloqueios_gerir on bloqueios;
create policy bloqueios_gerir on bloqueios for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));
