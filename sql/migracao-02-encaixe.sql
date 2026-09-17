-- ============================================================
-- BarberHub — migração 02
-- Permite o encaixe: atendimento lançado pela barbearia para
-- alguém que não tem conta na plataforma.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- o cliente deixa de ser obrigatório...
alter table agendamentos alter column cliente_id drop not null;

-- ...e no lugar dele entram nome e telefone digitados no balcão
alter table agendamentos add column if not exists cliente_nome text;
alter table agendamentos add column if not exists cliente_telefone text;

-- mas um dos dois tem de existir: ou a conta, ou o nome
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamentos_tem_cliente'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table agendamentos
      add constraint agendamentos_tem_cliente
      check (cliente_id is not null or cliente_nome is not null);
  end if;
end $$;

comment on column agendamentos.cliente_nome is
  'Nome do cliente sem conta, lançado pela barbearia (encaixe).';
