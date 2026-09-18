-- ============================================================
-- BarberHub — migração 12
-- Acesso do barbeiro: o dono cria o login, o profissional entra
-- e vê só a própria agenda.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- 1. O barbeiro passa a ter e-mail
-- É por ele que a conta é ligada ao profissional.
-- ------------------------------------------------------------
alter table barbeiros
  add column if not exists email text;

create unique index if not exists idx_barbeiros_email
  on barbeiros (estabelecimento_id, lower(email))
  where email is not null;

-- ------------------------------------------------------------
-- 2. Quando alguém se cadastra, amarra ao barbeiro de mesmo e-mail
-- Assim funciona nos dois sentidos: o dono pode cadastrar o
-- e-mail antes ou depois de a pessoa criar a conta.
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

  -- o dono já tinha cadastrado esse e-mail como profissional?
  update public.barbeiros
  set perfil_id = new.id
  where perfil_id is null
    and email is not null
    and lower(email) = lower(new.email);

  -- se virou barbeiro de alguém, o papel acompanha
  if exists (select 1 from public.barbeiros where perfil_id = new.id) then
    update public.perfis set papel = 'barbeiro'
    where id = new.id and papel = 'cliente';
  end if;

  return new;
end $$;

-- ------------------------------------------------------------
-- 3. Ligar um e-mail já existente a um barbeiro
-- Usado quando o dono cadastra o e-mail de quem já tem conta.
-- ------------------------------------------------------------
create or replace function public.vincular_barbeiro(p_barbeiro uuid, p_email text)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  alvo uuid;
  estab uuid;
begin
  select estabelecimento_id into estab from barbeiros where id = p_barbeiro;

  if estab is null or not public.gerencio_estab(estab) then
    return jsonb_build_object('ok', false, 'motivo', 'Sem permissão.');
  end if;

  select id into alvo from auth.users where lower(email) = lower(trim(p_email)) limit 1;

  if alvo is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_conta');
  end if;

  update barbeiros set perfil_id = alvo, email = lower(trim(p_email))
  where id = p_barbeiro;

  update perfis set papel = 'barbeiro' where id = alvo and papel = 'cliente';

  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.vincular_barbeiro to authenticated;

-- ------------------------------------------------------------
-- 4. Os estabelecimentos em que eu sou profissional
-- ------------------------------------------------------------
create or replace function public.onde_sou_barbeiro()
returns table (
  barbeiro_id uuid,
  estabelecimento_id uuid,
  nome_estabelecimento text,
  nome_barbeiro text
)
language sql stable security definer set search_path = public as $$
  select b.id, b.estabelecimento_id, e.nome, b.nome
  from barbeiros b
  join estabelecimentos e on e.id = b.estabelecimento_id
  where b.perfil_id = auth.uid() and b.ativo
  order by e.nome
$$;

grant execute on function public.onde_sou_barbeiro to authenticated;

-- ------------------------------------------------------------
-- 5. O barbeiro precisa enxergar o serviço e o cliente da agenda
-- dele. As políticas antigas só contemplavam dono e cliente.
-- ------------------------------------------------------------
drop policy if exists servicos_ler on servicos;
create policy servicos_ler on servicos for select to anon, authenticated
using (
  (ativo and public.estab_disponivel(estabelecimento_id))
  or public.gerencio_estab(estabelecimento_id)
  or exists (
    select 1 from barbeiros b
    where b.estabelecimento_id = servicos.estabelecimento_id
      and b.perfil_id = auth.uid()
  )
);

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
  -- e o barbeiro vê o cliente que marcou com ele
  or exists (
    select 1 from agendamentos a
    join barbeiros b on b.id = a.barbeiro_id
    where a.cliente_id = perfis.id and b.perfil_id = auth.uid()
  )
);
