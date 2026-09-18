-- ============================================================
-- BarberHub — migração 11
-- Cupons de desconto.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

do $$ begin
  create type tipo_desconto as enum ('percentual','valor');
exception when duplicate_object then null; end $$;

create table if not exists cupons (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  codigo              text not null,
  descricao           text,
  tipo                tipo_desconto not null default 'percentual',
  -- percentual: 0 a 100. valor: em centavos.
  valor               integer not null check (valor > 0),
  -- limita a um serviço; nulo vale para o atendimento todo
  servico_id          uuid references servicos(id) on delete cascade,
  minimo_centavos     integer not null default 0 check (minimo_centavos >= 0),
  usos_max            integer,
  usos_por_cliente    smallint not null default 1 check (usos_por_cliente > 0),
  inicio              date not null default current_date,
  fim                 date,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now(),
  unique (estabelecimento_id, codigo)
);

create index if not exists idx_cupons_estab on cupons (estabelecimento_id) where ativo;

create table if not exists cupom_usos (
  id              uuid primary key default gen_random_uuid(),
  cupom_id        uuid not null references cupons(id) on delete cascade,
  cliente_id      uuid references perfis(id) on delete set null,
  agendamento_id  uuid references agendamentos(id) on delete set null,
  desconto_centavos integer not null default 0,
  usado_em        timestamptz not null default now()
);

create index if not exists idx_cupom_usos on cupom_usos (cupom_id);
create index if not exists idx_cupom_usos_cliente on cupom_usos (cupom_id, cliente_id);

-- o agendamento guarda qual cupom entrou e quanto abateu
alter table agendamentos
  add column if not exists cupom_id uuid references cupons(id) on delete set null,
  add column if not exists desconto_cupom_centavos integer not null default 0;

-- ------------------------------------------------------------
-- Permissões
-- A lista de cupons é só do dono: se qualquer um pudesse ler a
-- tabela, bastaria abrir o navegador para descobrir os códigos.
-- A conferência acontece pela função abaixo.
-- ------------------------------------------------------------
alter table cupons enable row level security;
alter table cupom_usos enable row level security;

drop policy if exists cupons_gerir on cupons;
create policy cupons_gerir on cupons for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));

drop policy if exists cupom_usos_ler on cupom_usos;
create policy cupom_usos_ler on cupom_usos for select to authenticated
using (
  cliente_id = auth.uid()
  or exists (select 1 from cupons c
             where c.id = cupom_id and public.gerencio_estab(c.estabelecimento_id))
);

drop policy if exists cupom_usos_criar on cupom_usos;
create policy cupom_usos_criar on cupom_usos for insert to authenticated
with check (
  cliente_id = auth.uid()
  or exists (select 1 from cupons c
             where c.id = cupom_id and public.gerencio_estab(c.estabelecimento_id))
);

-- ------------------------------------------------------------
-- Conferir um cupom
-- Devolve se vale e quanto abate, sem expor a tabela.
-- O total vem em centavos, já com plano e descontos aplicados.
-- ------------------------------------------------------------
create or replace function public.validar_cupom(
  p_estab uuid, p_codigo text, p_total integer
)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c cupons%rowtype;
  usos_totais integer;
  usos_meus integer;
  abate integer;
begin
  select * into c from cupons
  where estabelecimento_id = p_estab
    and upper(codigo) = upper(trim(p_codigo))
    and ativo;

  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'Cupom não encontrado.');
  end if;

  if current_date < c.inicio then
    return jsonb_build_object('ok', false, 'motivo', 'Esse cupom ainda não começou a valer.');
  end if;

  if c.fim is not null and current_date > c.fim then
    return jsonb_build_object('ok', false, 'motivo', 'Esse cupom já venceu.');
  end if;

  if p_total < c.minimo_centavos then
    return jsonb_build_object('ok', false, 'motivo',
      'Esse cupom vale a partir de R$ ' || to_char(c.minimo_centavos / 100.0, 'FM999990.00') || '.');
  end if;

  select count(*) into usos_totais from cupom_usos where cupom_id = c.id;
  if c.usos_max is not null and usos_totais >= c.usos_max then
    return jsonb_build_object('ok', false, 'motivo', 'Esse cupom esgotou.');
  end if;

  select count(*) into usos_meus
  from cupom_usos where cupom_id = c.id and cliente_id = auth.uid();

  if usos_meus >= c.usos_por_cliente then
    return jsonb_build_object('ok', false, 'motivo', 'Você já usou esse cupom.');
  end if;

  abate := case c.tipo
    when 'percentual' then (p_total * c.valor) / 100
    else c.valor
  end;

  abate := least(abate, p_total);

  return jsonb_build_object(
    'ok', true,
    'cupom_id', c.id,
    'codigo', c.codigo,
    'descricao', c.descricao,
    'desconto', abate,
    'tipo', c.tipo,
    'valor', c.valor
  );
end $$;

grant execute on function public.validar_cupom to authenticated;
