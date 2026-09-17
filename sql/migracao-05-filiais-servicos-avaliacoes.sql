-- ============================================================
-- BarberHub — migração 05
-- Filiais, vários serviços por agendamento, avaliações,
-- planos de assinatura e cartão de fidelidade.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ============================================================
-- PARTE 1 — FILIAIS
-- Uma filial é um estabelecimento que aponta para a matriz.
-- Cada uma tem endereço, equipe, serviços e agenda próprios;
-- o que as une é o vínculo e o dono.
-- ============================================================
alter table estabelecimentos
  add column if not exists matriz_id uuid references estabelecimentos(id) on delete set null;

alter table estabelecimentos
  add column if not exists apelido_unidade text;

create index if not exists idx_estab_matriz on estabelecimentos (matriz_id);

comment on column estabelecimentos.matriz_id is
  'Nulo = unidade principal. Preenchido = filial da unidade indicada.';
comment on column estabelecimentos.apelido_unidade is
  'Como a filial é chamada internamente: Centro, Shopping, Matriz.';

-- ============================================================
-- PARTE 2 — VÁRIOS SERVIÇOS POR AGENDAMENTO
-- O agendamento passa a guardar o valor e a duração fechados
-- no momento da marcação. Se a barbearia mudar o preço depois,
-- o histórico não se altera.
-- ============================================================
alter table agendamentos
  add column if not exists valor_centavos integer not null default 0;

alter table agendamentos alter column servico_id drop not null;

create table if not exists agendamento_servicos (
  id              uuid primary key default gen_random_uuid(),
  agendamento_id  uuid not null references agendamentos(id) on delete cascade,
  servico_id      uuid not null references servicos(id) on delete restrict,
  nome            text not null,
  preco_centavos  integer not null check (preco_centavos >= 0),
  duracao_min     integer not null check (duracao_min > 0),
  ordem           smallint not null default 0
);

create index if not exists idx_ag_servicos on agendamento_servicos (agendamento_id, ordem);

-- Traz para a tabela nova o que já existe de agendamento antigo
insert into agendamento_servicos (agendamento_id, servico_id, nome, preco_centavos, duracao_min, ordem)
select a.id, s.id, s.nome, s.preco_centavos, s.duracao_min, 0
from agendamentos a
join servicos s on s.id = a.servico_id
where a.servico_id is not null
  and not exists (select 1 from agendamento_servicos x where x.agendamento_id = a.id);

-- E fecha o valor dos que ainda estão zerados
update agendamentos a
set valor_centavos = coalesce((
  select sum(v.preco_centavos) from agendamento_servicos v where v.agendamento_id = a.id
), 0)
where a.valor_centavos = 0;

-- Quem pode ver os itens: quem já podia ver o agendamento
create or replace function public.posso_ver_agendamento(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from agendamentos a
    where a.id = p_id
      and (a.cliente_id = auth.uid()
           or public.gerencio_estab(a.estabelecimento_id)
           or public.sou_barbeiro(a.barbeiro_id))
  )
$$;

create or replace function public.posso_editar_agendamento(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from agendamentos a
    where a.id = p_id
      and (a.cliente_id = auth.uid() or public.gerencio_estab(a.estabelecimento_id))
  )
$$;

grant execute on function public.posso_ver_agendamento, public.posso_editar_agendamento
to anon, authenticated;

alter table agendamento_servicos enable row level security;

drop policy if exists ag_servicos_ler on agendamento_servicos;
create policy ag_servicos_ler on agendamento_servicos for select to authenticated
using (public.posso_ver_agendamento(agendamento_id));

drop policy if exists ag_servicos_gerir on agendamento_servicos;
create policy ag_servicos_gerir on agendamento_servicos for all to authenticated
using (public.posso_editar_agendamento(agendamento_id))
with check (public.posso_editar_agendamento(agendamento_id));

-- ============================================================
-- PARTE 3 — AVALIAÇÕES
-- Uma avaliação por atendimento concluído, feita pelo cliente.
-- A barbearia pode responder, mas não pode mudar a nota.
-- ============================================================
create table if not exists avaliacoes (
  id                  uuid primary key default gen_random_uuid(),
  agendamento_id      uuid not null unique references agendamentos(id) on delete cascade,
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  barbeiro_id         uuid references barbeiros(id) on delete set null,
  cliente_id          uuid not null references perfis(id) on delete cascade,
  nota                smallint not null check (nota between 1 and 5),
  comentario          text,
  resposta            text,
  respondido_em       timestamptz,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_avaliacoes_estab on avaliacoes (estabelecimento_id, criado_em desc);
create index if not exists idx_avaliacoes_barbeiro on avaliacoes (barbeiro_id);

-- A média fica guardada no estabelecimento, para o card da busca
-- não precisar somar tudo a cada carregamento.
alter table estabelecimentos
  add column if not exists nota_media numeric(3,2),
  add column if not exists nota_qtd integer not null default 0;

create or replace function public.recalcular_nota()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  alvo uuid := coalesce(new.estabelecimento_id, old.estabelecimento_id);
begin
  update estabelecimentos e
  set nota_media = sub.media, nota_qtd = sub.qtd
  from (
    select round(avg(nota)::numeric, 2) as media, count(*) as qtd
    from avaliacoes where estabelecimento_id = alvo
  ) sub
  where e.id = alvo;
  return null;
end $$;

drop trigger if exists ao_mudar_avaliacao on avaliacoes;
create trigger ao_mudar_avaliacao
  after insert or update or delete on avaliacoes
  for each row execute function public.recalcular_nota();

alter table avaliacoes enable row level security;

-- Todo mundo lê as avaliações de quem está no catálogo
drop policy if exists avaliacoes_ler on avaliacoes;
create policy avaliacoes_ler on avaliacoes for select to anon, authenticated
using (
  public.estab_disponivel(estabelecimento_id)
  or public.gerencio_estab(estabelecimento_id)
  or cliente_id = auth.uid()
);

-- Só avalia quem foi atendido, e só o próprio atendimento
drop policy if exists avaliacoes_criar on avaliacoes;
create policy avaliacoes_criar on avaliacoes for insert to authenticated
with check (
  cliente_id = auth.uid()
  and exists (
    select 1 from agendamentos a
    where a.id = agendamento_id
      and a.cliente_id = auth.uid()
      and a.status = 'concluido'
      and a.estabelecimento_id = avaliacoes.estabelecimento_id
  )
);

-- O cliente edita a própria avaliação; a barbearia só responde
drop policy if exists avaliacoes_editar on avaliacoes;
create policy avaliacoes_editar on avaliacoes for update to authenticated
using (cliente_id = auth.uid() or public.gerencio_estab(estabelecimento_id))
with check (cliente_id = auth.uid() or public.gerencio_estab(estabelecimento_id));

drop policy if exists avaliacoes_apagar on avaliacoes;
create policy avaliacoes_apagar on avaliacoes for delete to authenticated
using (cliente_id = auth.uid() or public.e_admin());

-- Impede a barbearia de alterar a nota ao responder
create or replace function public.protege_nota()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is distinct from old.cliente_id then
    new.nota := old.nota;
    new.comentario := old.comentario;
    new.cliente_id := old.cliente_id;
    new.agendamento_id := old.agendamento_id;
  end if;
  if new.resposta is distinct from old.resposta then
    new.respondido_em := now();
  end if;
  return new;
end $$;

drop trigger if exists avaliacoes_protege on avaliacoes;
create trigger avaliacoes_protege
  before update on avaliacoes
  for each row execute function public.protege_nota();

-- ============================================================
-- PARTE 4 — PLANOS DE ASSINATURA E FIDELIDADE
-- Sem cobrança automática: a barbearia registra quem assinou.
-- O pagamento entra no passo 14 do roadmap.
-- ============================================================
do $$ begin
  create type periodicidade_plano as enum ('mensal','trimestral','semestral','anual');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_assinatura as enum ('ativa','pausada','cancelada','expirada');
exception when duplicate_object then null; end $$;

create table if not exists planos (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  nome                text not null,
  descricao           text,
  preco_centavos      integer not null check (preco_centavos >= 0),
  periodicidade       periodicidade_plano not null default 'mensal',
  -- quantos atendimentos o plano cobre por período; nulo = ilimitado
  usos_por_periodo    smallint,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_planos_estab on planos (estabelecimento_id) where ativo;

create table if not exists assinaturas (
  id                  uuid primary key default gen_random_uuid(),
  plano_id            uuid not null references planos(id) on delete restrict,
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  cliente_id          uuid references perfis(id) on delete set null,
  cliente_nome        text,
  cliente_telefone    text,
  inicio              date not null default current_date,
  fim                 date,
  status              status_assinatura not null default 'ativa',
  observacao          text,
  criado_em           timestamptz not null default now(),
  constraint assinaturas_tem_cliente check (cliente_id is not null or cliente_nome is not null)
);

create index if not exists idx_assinaturas_estab on assinaturas (estabelecimento_id, status);
create index if not exists idx_assinaturas_cliente on assinaturas (cliente_id);

-- Cartão de fidelidade: a cada N atendimentos concluídos, um prêmio
create table if not exists fidelidade (
  estabelecimento_id  uuid primary key references estabelecimentos(id) on delete cascade,
  atendimentos_alvo   smallint not null default 10 check (atendimentos_alvo between 2 and 100),
  premio              text not null default 'Um corte grátis',
  ativo               boolean not null default false,
  atualizado_em       timestamptz not null default now()
);

alter table planos       enable row level security;
alter table assinaturas  enable row level security;
alter table fidelidade   enable row level security;

drop policy if exists planos_ler on planos;
create policy planos_ler on planos for select to anon, authenticated
using (
  (ativo and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
);

drop policy if exists planos_gerir on planos;
create policy planos_gerir on planos for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));

drop policy if exists assinaturas_ler on assinaturas;
create policy assinaturas_ler on assinaturas for select to authenticated
using (cliente_id = auth.uid() or public.gerencio_estab(estabelecimento_id));

drop policy if exists assinaturas_gerir on assinaturas;
create policy assinaturas_gerir on assinaturas for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));

drop policy if exists fidelidade_ler on fidelidade;
create policy fidelidade_ler on fidelidade for select to anon, authenticated
using (
  (ativo and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
);

drop policy if exists fidelidade_gerir on fidelidade;
create policy fidelidade_gerir on fidelidade for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));
