-- ============================================================
-- BarberHub — migração 08
-- Produtos, estoque, comandas e comissões.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- Tipos
-- ------------------------------------------------------------
do $$ begin
  create type status_comanda as enum ('aberta','fechada','cancelada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_item as enum ('servico','produto','avulso');
exception when duplicate_object then null; end $$;

do $$ begin
  create type forma_pagamento as enum ('dinheiro','pix','credito','debito','plano','cortesia','outro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type movimento_estoque as enum ('entrada','saida','ajuste','venda','devolucao');
exception when duplicate_object then null; end $$;

do $$ begin
  create type base_comissao as enum ('cobrado','tabela');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- 1. Regras de comissão
-- Sobre o que a comissão incide: o que o cliente pagou
-- ("cobrado") ou o preço de tabela ("tabela"). Muda o resultado
-- para assinante, que às vezes paga zero.
-- ------------------------------------------------------------
alter table estabelecimentos
  add column if not exists base_comissao base_comissao not null default 'cobrado';

alter table barbeiros
  add column if not exists comissao_pct numeric(5,2) not null default 0
    check (comissao_pct between 0 and 100),
  add column if not exists comissao_produtos_pct numeric(5,2) not null default 0
    check (comissao_produtos_pct between 0 and 100);

-- percentual próprio do serviço; nulo = usa o do barbeiro
alter table servicos
  add column if not exists comissao_pct numeric(5,2)
    check (comissao_pct is null or comissao_pct between 0 and 100);

-- ------------------------------------------------------------
-- 2. Produtos e estoque
-- ------------------------------------------------------------
create table if not exists produtos (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  nome                text not null,
  descricao           text,
  preco_centavos      integer not null check (preco_centavos >= 0),
  custo_centavos      integer not null default 0 check (custo_centavos >= 0),
  estoque             integer not null default 0,
  estoque_minimo      integer not null default 0,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_produtos_estab on produtos (estabelecimento_id) where ativo;

create table if not exists movimentos_estoque (
  id           uuid primary key default gen_random_uuid(),
  produto_id   uuid not null references produtos(id) on delete cascade,
  tipo         movimento_estoque not null,
  quantidade   integer not null,
  motivo       text,
  criado_em    timestamptz not null default now()
);

create index if not exists idx_movimentos on movimentos_estoque (produto_id, criado_em desc);

-- ------------------------------------------------------------
-- 3. Comandas
-- ------------------------------------------------------------
create table if not exists comandas (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  agendamento_id      uuid references agendamentos(id) on delete set null,
  barbeiro_id         uuid references barbeiros(id) on delete set null,
  cliente_id          uuid references perfis(id) on delete set null,
  cliente_nome        text,
  cliente_telefone    text,
  status              status_comanda not null default 'aberta',
  desconto_centavos   integer not null default 0 check (desconto_centavos >= 0),
  total_centavos      integer not null default 0,
  comissao_centavos   integer not null default 0,
  forma_pagamento     forma_pagamento,
  observacao          text,
  aberta_em           timestamptz not null default now(),
  fechada_em          timestamptz
);

create index if not exists idx_comandas_estab on comandas (estabelecimento_id, aberta_em desc);
create index if not exists idx_comandas_status on comandas (estabelecimento_id, status);
create unique index if not exists idx_comandas_agendamento
  on comandas (agendamento_id) where agendamento_id is not null;

create table if not exists comanda_itens (
  id                  uuid primary key default gen_random_uuid(),
  comanda_id          uuid not null references comandas(id) on delete cascade,
  tipo                tipo_item not null,
  servico_id          uuid references servicos(id) on delete set null,
  produto_id          uuid references produtos(id) on delete set null,
  barbeiro_id         uuid references barbeiros(id) on delete set null,
  nome                text not null,
  quantidade          smallint not null default 1 check (quantidade > 0),
  preco_unit_centavos integer not null check (preco_unit_centavos >= 0),
  desconto_pct        numeric(5,2) not null default 0 check (desconto_pct between 0 and 100),
  total_centavos      integer not null default 0,
  comissao_pct        numeric(5,2) not null default 0,
  comissao_centavos   integer not null default 0,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_comanda_itens on comanda_itens (comanda_id);
create index if not exists idx_comanda_itens_barbeiro on comanda_itens (barbeiro_id);

-- ------------------------------------------------------------
-- 4. O estoque se move sozinho com o item de produto
-- ------------------------------------------------------------
create or replace function public.mexer_estoque()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.tipo = 'produto' and new.produto_id is not null then
    update produtos set estoque = estoque - new.quantidade where id = new.produto_id;
    insert into movimentos_estoque (produto_id, tipo, quantidade, motivo)
    values (new.produto_id, 'venda', -new.quantidade, 'Venda em comanda');

  elsif tg_op = 'DELETE' and old.tipo = 'produto' and old.produto_id is not null then
    update produtos set estoque = estoque + old.quantidade where id = old.produto_id;
    insert into movimentos_estoque (produto_id, tipo, quantidade, motivo)
    values (old.produto_id, 'devolucao', old.quantidade, 'Item removido da comanda');
  end if;

  return coalesce(new, old);
end $$;

drop trigger if exists ao_mexer_item on comanda_itens;
create trigger ao_mexer_item
  after insert or delete on comanda_itens
  for each row execute function public.mexer_estoque();

-- ------------------------------------------------------------
-- 5. O total da comanda acompanha os itens
-- ------------------------------------------------------------
create or replace function public.recalcular_comanda()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  alvo uuid := coalesce(new.comanda_id, old.comanda_id);
begin
  update comandas c
  set total_centavos = greatest(0, coalesce(sub.soma, 0) - c.desconto_centavos),
      comissao_centavos = coalesce(sub.comissao, 0)
  from (
    select sum(total_centavos) as soma, sum(comissao_centavos) as comissao
    from comanda_itens where comanda_id = alvo
  ) sub
  where c.id = alvo;
  return null;
end $$;

drop trigger if exists ao_mudar_item on comanda_itens;
create trigger ao_mudar_item
  after insert or update or delete on comanda_itens
  for each row execute function public.recalcular_comanda();

-- ------------------------------------------------------------
-- 6. Permissões
-- Comanda é assunto interno: o cliente não lê.
-- ------------------------------------------------------------
alter table produtos            enable row level security;
alter table movimentos_estoque  enable row level security;
alter table comandas            enable row level security;
alter table comanda_itens       enable row level security;

drop policy if exists produtos_ler on produtos;
create policy produtos_ler on produtos for select to anon, authenticated
using (
  (ativo and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
);

drop policy if exists produtos_gerir on produtos;
create policy produtos_gerir on produtos for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));

drop policy if exists movimentos_ler on movimentos_estoque;
create policy movimentos_ler on movimentos_estoque for select to authenticated
using (exists (
  select 1 from produtos p
  where p.id = produto_id and public.gerencio_estab(p.estabelecimento_id)
));

drop policy if exists movimentos_gerir on movimentos_estoque;
create policy movimentos_gerir on movimentos_estoque for all to authenticated
using (exists (
  select 1 from produtos p
  where p.id = produto_id and public.gerencio_estab(p.estabelecimento_id)
))
with check (exists (
  select 1 from produtos p
  where p.id = produto_id and public.gerencio_estab(p.estabelecimento_id)
));

drop policy if exists comandas_gerir on comandas;
create policy comandas_gerir on comandas for all to authenticated
using (public.gerencio_estab(estabelecimento_id) or public.sou_barbeiro(barbeiro_id))
with check (public.gerencio_estab(estabelecimento_id));

create or replace function public.minha_comanda(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from comandas c
    where c.id = p_id
      and (public.gerencio_estab(c.estabelecimento_id) or public.sou_barbeiro(c.barbeiro_id))
  )
$$;

grant execute on function public.minha_comanda to authenticated;

drop policy if exists comanda_itens_gerir on comanda_itens;
create policy comanda_itens_gerir on comanda_itens for all to authenticated
using (public.minha_comanda(comanda_id))
with check (public.minha_comanda(comanda_id));
