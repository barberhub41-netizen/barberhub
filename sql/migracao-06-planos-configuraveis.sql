-- ============================================================
-- BarberHub — migração 06
-- Planos configuráveis: cota por serviço, desconto no que passa
-- da cota e desconto nos demais serviços e produtos.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- 1. O plano ganha as regras gerais
-- ------------------------------------------------------------
alter table planos
  -- desconto no que NÃO está na lista de incluídos
  add column if not exists desconto_servicos_pct numeric(5,2) not null default 0
    check (desconto_servicos_pct between 0 and 100),
  -- reservado: só terá efeito quando existir venda de produto
  add column if not exists desconto_produtos_pct numeric(5,2) not null default 0
    check (desconto_produtos_pct between 0 and 100),
  add column if not exists renova_automatico boolean not null default true,
  add column if not exists cor text;

comment on column planos.usos_por_periodo is
  'Teto geral de atendimentos cobertos no período, somando todos os serviços. Nulo = sem teto geral.';

-- ------------------------------------------------------------
-- 2. O que cada plano cobre, serviço a serviço
-- quantidade nula = ilimitado naquele serviço
-- desconto_excedente_pct = desconto depois de esgotar a cota
-- ------------------------------------------------------------
create table if not exists plano_itens (
  id                      uuid primary key default gen_random_uuid(),
  plano_id                uuid not null references planos(id) on delete cascade,
  servico_id              uuid not null references servicos(id) on delete cascade,
  quantidade              smallint check (quantidade is null or quantidade > 0),
  desconto_excedente_pct  numeric(5,2) not null default 0
    check (desconto_excedente_pct between 0 and 100),
  unique (plano_id, servico_id)
);

create index if not exists idx_plano_itens on plano_itens (plano_id);

alter table plano_itens enable row level security;

drop policy if exists plano_itens_ler on plano_itens;
create policy plano_itens_ler on plano_itens for select to anon, authenticated
using (exists (
  select 1 from planos p
  where p.id = plano_id
    and ((p.ativo and public.estab_disponivel(p.estabelecimento_id))
         or public.gerencio_estab(p.estabelecimento_id))
));

drop policy if exists plano_itens_gerir on plano_itens;
create policy plano_itens_gerir on plano_itens for all to authenticated
using (exists (
  select 1 from planos p
  where p.id = plano_id and public.gerencio_estab(p.estabelecimento_id)
))
with check (exists (
  select 1 from planos p
  where p.id = plano_id and public.gerencio_estab(p.estabelecimento_id)
));

-- ------------------------------------------------------------
-- 3. O atendimento passa a saber de qual assinatura veio
-- ------------------------------------------------------------
alter table agendamentos
  add column if not exists assinatura_id uuid references assinaturas(id) on delete set null;

create index if not exists idx_agend_assinatura on agendamentos (assinatura_id);

-- ------------------------------------------------------------
-- 4. Cada item guarda como foi cobrado
-- preco_centavos     = valor de tabela no dia
-- preco_cobrado_centavos = o que o cliente realmente paga
-- coberto            = entrou na cota do plano, sai por zero
-- ------------------------------------------------------------
alter table agendamento_servicos
  add column if not exists coberto boolean not null default false,
  add column if not exists desconto_pct numeric(5,2) not null default 0
    check (desconto_pct between 0 and 100),
  add column if not exists preco_cobrado_centavos integer;

update agendamento_servicos
set preco_cobrado_centavos = preco_centavos
where preco_cobrado_centavos is null;

-- ------------------------------------------------------------
-- 5. Quanto de cada serviço a assinatura já consumiu no ciclo
-- Recebe o começo e o fim do ciclo calculados pelo aplicativo.
-- ------------------------------------------------------------
create or replace function public.consumo_assinatura(
  p_assinatura uuid, p_de timestamptz, p_ate timestamptz
)
returns table (servico_id uuid, usados bigint)
language sql stable security definer set search_path = public as $$
  select v.servico_id, count(*)::bigint
  from agendamentos a
  join agendamento_servicos v on v.agendamento_id = a.id
  where a.assinatura_id = p_assinatura
    and v.coberto
    and a.status in ('pendente','confirmado','concluido')
    and a.inicio >= p_de and a.inicio < p_ate
  group by v.servico_id
$$;

grant execute on function public.consumo_assinatura to authenticated;
