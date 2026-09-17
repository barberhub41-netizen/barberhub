-- ============================================================
-- BarberHub — esquema inicial (passo 1 do roadmap)
-- Rodar no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- ============================================================

create extension if not exists btree_gist;

-- ------------------------------------------------------------
-- Tipos
-- ------------------------------------------------------------
do $$ begin
  create type papel_usuario as enum ('cliente','barbeiro','gestor','admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_estabelecimento as enum ('rascunho','disponivel','suspenso');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_agendamento as enum ('pendente','confirmado','concluido','cancelado','faltou');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- 1. perfis — complementa o auth.users do Supabase
-- ------------------------------------------------------------
create table if not exists perfis (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text not null,
  telefone    text,
  papel       papel_usuario not null default 'cliente',
  criado_em   timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. estabelecimentos
-- ------------------------------------------------------------
create table if not exists estabelecimentos (
  id            uuid primary key default gen_random_uuid(),
  dono_id       uuid not null references perfis(id) on delete restrict,
  nome          text not null,
  slug          text not null unique,
  descricao     text,
  telefone      text,
  cep           text,
  logradouro    text,
  numero        text,
  bairro        text,
  cidade        text not null,
  uf            char(2) not null,
  latitude      double precision,
  longitude     double precision,
  status        status_estabelecimento not null default 'rascunho',
  criado_em     timestamptz not null default now()
);

create index if not exists idx_estab_busca on estabelecimentos (cidade, status);
create index if not exists idx_estab_dono  on estabelecimentos (dono_id);

-- ------------------------------------------------------------
-- 3. barbeiros
-- perfil_id fica nulo enquanto o barbeiro não tiver login próprio
-- ------------------------------------------------------------
create table if not exists barbeiros (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  perfil_id           uuid references perfis(id) on delete set null,
  nome                text not null,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_barbeiros_estab on barbeiros (estabelecimento_id) where ativo;

-- ------------------------------------------------------------
-- 4. servicos
-- preco em CENTAVOS (inteiro) — evita erro de arredondamento
-- ------------------------------------------------------------
create table if not exists servicos (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  nome                text not null,
  descricao           text,
  preco_centavos      integer not null check (preco_centavos >= 0),
  duracao_min         integer not null check (duracao_min between 5 and 600),
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_servicos_estab on servicos (estabelecimento_id) where ativo;

-- ------------------------------------------------------------
-- 5. jornadas — horário de trabalho por barbeiro e dia da semana
-- dia_semana: 0 = domingo ... 6 = sábado
-- ------------------------------------------------------------
create table if not exists jornadas (
  id           uuid primary key default gen_random_uuid(),
  barbeiro_id  uuid not null references barbeiros(id) on delete cascade,
  dia_semana   smallint not null check (dia_semana between 0 and 6),
  hora_inicio  time not null,
  hora_fim     time not null,
  check (hora_fim > hora_inicio)
);

create index if not exists idx_jornadas_barbeiro on jornadas (barbeiro_id, dia_semana);

-- ------------------------------------------------------------
-- 6. agendamentos
-- inicio/fim em timestamptz — o Postgres guarda em UTC sozinho
-- ------------------------------------------------------------
create table if not exists agendamentos (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  barbeiro_id         uuid not null references barbeiros(id) on delete restrict,
  servico_id          uuid not null references servicos(id) on delete restrict,
  cliente_id          uuid not null references perfis(id) on delete restrict,
  inicio              timestamptz not null,
  fim                 timestamptz not null,
  status              status_agendamento not null default 'pendente',
  observacao          text,
  criado_em           timestamptz not null default now(),
  check (fim > inicio)
);

create index if not exists idx_agend_barbeiro on agendamentos (barbeiro_id, inicio);
create index if not exists idx_agend_cliente  on agendamentos (cliente_id, inicio desc);
create index if not exists idx_agend_estab    on agendamentos (estabelecimento_id, inicio);

-- Impede dois agendamentos no mesmo barbeiro com horários sobrepostos.
-- O próprio banco recusa o conflito, mesmo se dois clientes clicarem juntos.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamentos_sem_conflito'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table agendamentos
      add constraint agendamentos_sem_conflito
      exclude using gist (
        barbeiro_id with =,
        tstzrange(inicio, fim) with &&
      ) where (status in ('pendente','confirmado'));
  end if;
end $$;

-- ------------------------------------------------------------
-- Segurança: liga o RLS em tudo.
-- Sem políticas criadas, a API pública não lê nem escreve nada.
-- As políticas entram no passo 2 (login e perfis de acesso).
-- ------------------------------------------------------------
alter table perfis            enable row level security;
alter table estabelecimentos  enable row level security;
alter table barbeiros         enable row level security;
alter table servicos          enable row level security;
alter table jornadas          enable row level security;
alter table agendamentos      enable row level security;

-- ------------------------------------------------------------
-- Cria o perfil automaticamente quando alguém se cadastra
-- ------------------------------------------------------------
create or replace function public.criar_perfil_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfis (id, nome, telefone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'telefone'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function public.criar_perfil_novo_usuario();
