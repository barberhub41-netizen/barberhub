-- ============================================================
-- BarberHub — permissões (passo 2 do roadmap)
-- Rodar no SQL Editor do Supabase, depois do barberhub-schema.sql.
-- Pode rodar quantas vezes quiser.
-- ============================================================

-- ------------------------------------------------------------
-- Funções auxiliares
-- São "security definer": enxergam as tabelas sem passar pelo RLS,
-- o que evita a política consultar a própria tabela em loop.
-- ------------------------------------------------------------

create or replace function public.meu_papel()
returns papel_usuario language sql stable security definer set search_path = public as $$
  select papel from perfis where id = auth.uid()
$$;

create or replace function public.e_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.meu_papel() = 'admin', false)
$$;

-- Sou dono do estabelecimento (ou admin)?
create or replace function public.gerencio_estab(p_estab uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.e_admin() or exists (
    select 1 from estabelecimentos e
    where e.id = p_estab and e.dono_id = auth.uid()
  )
$$;

-- Esse registro de barbeiro é o meu?
create or replace function public.sou_barbeiro(p_barbeiro uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from barbeiros b
    where b.id = p_barbeiro and b.perfil_id = auth.uid()
  )
$$;

-- O estabelecimento está no catálogo público?
create or replace function public.estab_disponivel(p_estab uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from estabelecimentos e
    where e.id = p_estab and e.status = 'disponivel'
  )
$$;

create or replace function public.estab_do_barbeiro(p_barbeiro uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select estabelecimento_id from barbeiros where id = p_barbeiro
$$;

grant execute on function
  public.meu_papel, public.e_admin, public.gerencio_estab,
  public.sou_barbeiro, public.estab_disponivel, public.estab_do_barbeiro
to anon, authenticated;

-- ------------------------------------------------------------
-- Ninguém muda o próprio papel. Só admin promove alguém.
-- ------------------------------------------------------------
create or replace function public.protege_papel()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.papel is distinct from old.papel and not public.e_admin() then
    new.papel := old.papel;
  end if;
  return new;
end $$;

drop trigger if exists perfis_protege_papel on perfis;
create trigger perfis_protege_papel
  before update on perfis
  for each row execute function public.protege_papel();

-- ------------------------------------------------------------
-- perfis
-- ------------------------------------------------------------
drop policy if exists perfis_ler on perfis;
create policy perfis_ler on perfis for select to authenticated
using (
  id = auth.uid()
  or public.e_admin()
  -- o estabelecimento vê o cliente que marcou com ele
  or exists (
    select 1 from agendamentos a
    where a.cliente_id = perfis.id
      and public.gerencio_estab(a.estabelecimento_id)
  )
);

drop policy if exists perfis_criar on perfis;
create policy perfis_criar on perfis for insert to authenticated
with check (id = auth.uid());

drop policy if exists perfis_editar on perfis;
create policy perfis_editar on perfis for update to authenticated
using (id = auth.uid() or public.e_admin())
with check (id = auth.uid() or public.e_admin());

-- ------------------------------------------------------------
-- estabelecimentos
-- Catálogo é público: quem não está logado vê os "disponivel".
-- ------------------------------------------------------------
drop policy if exists estab_ler on estabelecimentos;
create policy estab_ler on estabelecimentos for select to anon, authenticated
using (status = 'disponivel' or dono_id = auth.uid() or public.e_admin());

drop policy if exists estab_criar on estabelecimentos;
create policy estab_criar on estabelecimentos for insert to authenticated
with check (dono_id = auth.uid());

drop policy if exists estab_editar on estabelecimentos;
create policy estab_editar on estabelecimentos for update to authenticated
using (dono_id = auth.uid() or public.e_admin())
with check (dono_id = auth.uid() or public.e_admin());

drop policy if exists estab_apagar on estabelecimentos;
create policy estab_apagar on estabelecimentos for delete to authenticated
using (dono_id = auth.uid() or public.e_admin());

-- ------------------------------------------------------------
-- barbeiros
-- ------------------------------------------------------------
drop policy if exists barbeiros_ler on barbeiros;
create policy barbeiros_ler on barbeiros for select to anon, authenticated
using (
  (ativo and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
  or perfil_id = auth.uid()
);

drop policy if exists barbeiros_gerir on barbeiros;
create policy barbeiros_gerir on barbeiros for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));

-- ------------------------------------------------------------
-- servicos
-- ------------------------------------------------------------
drop policy if exists servicos_ler on servicos;
create policy servicos_ler on servicos for select to anon, authenticated
using (
  (ativo and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
);

drop policy if exists servicos_gerir on servicos;
create policy servicos_gerir on servicos for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));

-- ------------------------------------------------------------
-- jornadas
-- Leitura pública: é o que permite calcular os horários livres.
-- ------------------------------------------------------------
drop policy if exists jornadas_ler on jornadas;
create policy jornadas_ler on jornadas for select to anon, authenticated
using (
  public.estab_disponivel(public.estab_do_barbeiro(barbeiro_id))
  or public.gerencio_estab(public.estab_do_barbeiro(barbeiro_id))
  or public.sou_barbeiro(barbeiro_id)
);

drop policy if exists jornadas_gerir on jornadas;
create policy jornadas_gerir on jornadas for all to authenticated
using (public.gerencio_estab(public.estab_do_barbeiro(barbeiro_id)))
with check (public.gerencio_estab(public.estab_do_barbeiro(barbeiro_id)));

-- ------------------------------------------------------------
-- agendamentos
-- ------------------------------------------------------------
drop policy if exists agend_ler on agendamentos;
create policy agend_ler on agendamentos for select to authenticated
using (
  cliente_id = auth.uid()
  or public.sou_barbeiro(barbeiro_id)
  or public.gerencio_estab(estabelecimento_id)
);

-- O cliente marca para si mesmo, e só em estabelecimento disponível.
-- O gestor também pode lançar um atendimento de balcão.
drop policy if exists agend_criar on agendamentos;
create policy agend_criar on agendamentos for insert to authenticated
with check (
  (cliente_id = auth.uid() and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
);

drop policy if exists agend_editar on agendamentos;
create policy agend_editar on agendamentos for update to authenticated
using (
  cliente_id = auth.uid()
  or public.sou_barbeiro(barbeiro_id)
  or public.gerencio_estab(estabelecimento_id)
)
with check (
  cliente_id = auth.uid()
  or public.sou_barbeiro(barbeiro_id)
  or public.gerencio_estab(estabelecimento_id)
);

-- Sem delete: cancelamento é status = 'cancelado', para não perder histórico.
drop policy if exists agend_apagar on agendamentos;
create policy agend_apagar on agendamentos for delete to authenticated
using (public.e_admin());

-- ------------------------------------------------------------
-- bloqueios (almoço, pausa, folga, férias)
-- A tabela nasce na migração 03. Este trecho só roda se ela já
-- existir, para que este arquivo possa ser executado antes ou
-- depois da migração, em qualquer ordem.
-- ------------------------------------------------------------
do $$ begin
  if to_regclass('public.bloqueios') is null then
    raise notice 'Tabela bloqueios ainda nao existe — rode a migracao 03 depois deste arquivo.';
    return;
  end if;

  execute 'alter table bloqueios enable row level security';

  execute 'drop policy if exists bloqueios_ler on bloqueios';
  execute $p$
    create policy bloqueios_ler on bloqueios for select to anon, authenticated
    using (
      public.estab_disponivel(estabelecimento_id)
      or public.gerencio_estab(estabelecimento_id)
      or public.sou_barbeiro(barbeiro_id)
    )
  $p$;

  execute 'drop policy if exists bloqueios_gerir on bloqueios';
  execute $p$
    create policy bloqueios_gerir on bloqueios for all to authenticated
    using (public.gerencio_estab(estabelecimento_id))
    with check (public.gerencio_estab(estabelecimento_id))
  $p$;
end $$;
