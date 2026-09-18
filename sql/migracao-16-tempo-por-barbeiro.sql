-- ============================================================
-- BarberHub — migração 16
-- Cada profissional pode ter o próprio tempo em cada serviço,
-- e pode não atender determinado serviço.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

create table if not exists barbeiro_servicos (
  id           uuid primary key default gen_random_uuid(),
  barbeiro_id  uuid not null references barbeiros(id) on delete cascade,
  servico_id   uuid not null references servicos(id) on delete cascade,
  -- nulo = usa a duração padrão do serviço
  duracao_min  integer check (duracao_min is null or duracao_min between 5 and 600),
  -- falso = esse profissional não faz esse serviço
  atende       boolean not null default true,
  criado_em    timestamptz not null default now(),
  unique (barbeiro_id, servico_id)
);

create index if not exists idx_barbeiro_servicos on barbeiro_servicos (barbeiro_id);
create index if not exists idx_barbeiro_servicos_srv on barbeiro_servicos (servico_id);

comment on table barbeiro_servicos is
  'Ajuste por profissional. Sem linha aqui, vale o padrão do serviço e todos atendem.';

-- ------------------------------------------------------------
-- Permissões
-- Leitura pública: o cliente precisa saber quanto tempo aquele
-- profissional leva, senão os horários oferecidos ficam errados.
-- ------------------------------------------------------------
alter table barbeiro_servicos enable row level security;

drop policy if exists barbeiro_servicos_ler on barbeiro_servicos;
create policy barbeiro_servicos_ler on barbeiro_servicos for select to anon, authenticated
using (exists (
  select 1 from barbeiros b
  where b.id = barbeiro_id
    and (public.estab_disponivel(b.estabelecimento_id)
         or public.gerencio_estab(b.estabelecimento_id)
         or b.perfil_id = auth.uid())
));

drop policy if exists barbeiro_servicos_gerir on barbeiro_servicos;
create policy barbeiro_servicos_gerir on barbeiro_servicos for all to authenticated
using (exists (
  select 1 from barbeiros b
  where b.id = barbeiro_id and public.gerencio_estab(b.estabelecimento_id)
))
with check (exists (
  select 1 from barbeiros b
  where b.id = barbeiro_id and public.gerencio_estab(b.estabelecimento_id)
));
