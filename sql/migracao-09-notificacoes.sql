-- ============================================================
-- BarberHub — migração 09
-- Avisos dentro do site: sino no topo, sem servidor nem e-mail.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

do $$ begin
  create type tipo_aviso as enum (
    'agendamento_novo','agendamento_confirmado','agendamento_cancelado',
    'agendamento_concluido','avaliacao_nova','avaliacao_respondida','aviso'
  );
exception when duplicate_object then null; end $$;

create table if not exists notificacoes (
  id              uuid primary key default gen_random_uuid(),
  destinatario_id uuid not null references perfis(id) on delete cascade,
  tipo            tipo_aviso not null default 'aviso',
  titulo          text not null,
  mensagem        text,
  link            text,
  lida            boolean not null default false,
  criado_em       timestamptz not null default now()
);

create index if not exists idx_notif_pessoa
  on notificacoes (destinatario_id, lida, criado_em desc);

alter table notificacoes enable row level security;

-- cada um vê e marca como lida só as suas
drop policy if exists notificacoes_minhas on notificacoes;
create policy notificacoes_minhas on notificacoes for select to authenticated
using (destinatario_id = auth.uid());

drop policy if exists notificacoes_marcar on notificacoes;
create policy notificacoes_marcar on notificacoes for update to authenticated
using (destinatario_id = auth.uid())
with check (destinatario_id = auth.uid());

drop policy if exists notificacoes_apagar on notificacoes;
create policy notificacoes_apagar on notificacoes for delete to authenticated
using (destinatario_id = auth.uid());

-- ------------------------------------------------------------
-- Quem é o dono do estabelecimento
-- ------------------------------------------------------------
create or replace function public.dono_de(p_estab uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select dono_id from estabelecimentos where id = p_estab
$$;

-- ------------------------------------------------------------
-- Novo agendamento avisa a barbearia
-- ------------------------------------------------------------
create or replace function public.avisar_agendamento_novo()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  dono uuid := public.dono_de(new.estabelecimento_id);
  quem text;
begin
  -- se foi a própria barbearia que lançou, não precisa avisar
  if dono is null or dono = auth.uid() then return new; end if;

  select coalesce(p.nome, new.cliente_nome, 'Um cliente')
  into quem from perfis p where p.id = new.cliente_id;

  insert into notificacoes (destinatario_id, tipo, titulo, mensagem, link)
  values (
    dono, 'agendamento_novo',
    'Novo agendamento',
    coalesce(quem, 'Um cliente') || ' marcou para ' ||
      to_char(new.inicio at time zone 'America/Sao_Paulo', 'DD/MM às HH24:MI') || '.',
    'agenda.html'
  );
  return new;
end $$;

drop trigger if exists ao_agendar on agendamentos;
create trigger ao_agendar
  after insert on agendamentos
  for each row execute function public.avisar_agendamento_novo();

-- ------------------------------------------------------------
-- Mudança de status avisa o outro lado
-- ------------------------------------------------------------
create or replace function public.avisar_mudanca_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  dono uuid := public.dono_de(new.estabelecimento_id);
  quem_recebe uuid;
  nome_estab text;
  quem text;
  titulo text;
  tipo tipo_aviso;
begin
  if new.status = old.status then return new; end if;

  select nome into nome_estab from estabelecimentos where id = new.estabelecimento_id;

  -- quem mexeu não recebe o próprio aviso
  if auth.uid() = new.cliente_id then
    quem_recebe := dono;
  else
    quem_recebe := new.cliente_id;
  end if;

  if quem_recebe is null or quem_recebe = auth.uid() then return new; end if;

  tipo := case new.status
    when 'confirmado' then 'agendamento_confirmado'::tipo_aviso
    when 'cancelado'  then 'agendamento_cancelado'::tipo_aviso
    when 'concluido'  then 'agendamento_concluido'::tipo_aviso
    else 'aviso'::tipo_aviso
  end;

  titulo := case new.status
    when 'confirmado' then 'Horário confirmado'
    when 'cancelado'  then 'Horário cancelado'
    when 'concluido'  then 'Atendimento concluído'
    when 'faltou'     then 'Marcado como não comparecido'
    else 'Agendamento atualizado'
  end;

  if quem_recebe = dono then
    select coalesce(p.nome, new.cliente_nome, 'Um cliente')
    into quem from perfis p where p.id = new.cliente_id;

    insert into notificacoes (destinatario_id, tipo, titulo, mensagem, link)
    values (dono, tipo, titulo,
      coalesce(quem, 'Um cliente') || ' — ' ||
      to_char(new.inicio at time zone 'America/Sao_Paulo', 'DD/MM às HH24:MI') || '.',
      'agenda.html');
  else
    insert into notificacoes (destinatario_id, tipo, titulo, mensagem, link)
    values (quem_recebe, tipo, titulo,
      coalesce(nome_estab, 'A barbearia') || ' — ' ||
      to_char(new.inicio at time zone 'America/Sao_Paulo', 'DD/MM às HH24:MI') ||
      case when new.status = 'concluido' then '. Que tal avaliar?' else '.' end,
      'meus-agendamentos.html');
  end if;

  return new;
end $$;

drop trigger if exists ao_mudar_status on agendamentos;
create trigger ao_mudar_status
  after update of status on agendamentos
  for each row execute function public.avisar_mudanca_status();

-- ------------------------------------------------------------
-- Avaliação avisa a barbearia; a resposta avisa o cliente
-- ------------------------------------------------------------
create or replace function public.avisar_avaliacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  dono uuid := public.dono_de(new.estabelecimento_id);
  nome_estab text;
  quem text;
begin
  if tg_op = 'INSERT' then
    if dono is null or dono = auth.uid() then return new; end if;
    select nome into quem from perfis where id = new.cliente_id;
    insert into notificacoes (destinatario_id, tipo, titulo, mensagem, link)
    values (dono, 'avaliacao_nova', 'Nova avaliação',
      coalesce(quem, 'Um cliente') || ' deu ' || new.nota || ' de 5.',
      'avaliacoes.html');

  elsif new.resposta is distinct from old.resposta and new.resposta is not null then
    select nome into nome_estab from estabelecimentos where id = new.estabelecimento_id;
    insert into notificacoes (destinatario_id, tipo, titulo, mensagem, link)
    values (new.cliente_id, 'avaliacao_respondida', 'Responderam sua avaliação',
      coalesce(nome_estab, 'A barbearia') || ' respondeu o que você escreveu.',
      'meus-agendamentos.html');
  end if;

  return new;
end $$;

drop trigger if exists ao_avaliar on avaliacoes;
create trigger ao_avaliar
  after insert or update of resposta on avaliacoes
  for each row execute function public.avisar_avaliacao();
