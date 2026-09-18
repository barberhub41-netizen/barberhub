-- ============================================================
-- BarberHub — migração 14
-- Entrada pelo Google: puxa nome, e-mail e foto.
-- E prepara a busca por CPF, usada no login.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Foto vinda de fora
-- A foto do Google é uma URL, não um arquivo nosso. Guardamos
-- separada da que a pessoa envia pelo perfil.
-- ------------------------------------------------------------
alter table perfis
  add column if not exists foto_url text;

-- ------------------------------------------------------------
-- 2. O cadastro aproveita o que o provedor mandou
-- O Google devolve full_name/name, picture/avatar_url e o e-mail
-- já confirmado. Assim a pessoa só precisa completar o CPF.
-- ------------------------------------------------------------
create or replace function public.criar_perfil_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  n text := regexp_replace(coalesce(m->>'cpf', ''), '\D', '', 'g');
  nome_achado text;
  foto_achada text;
begin
  nome_achado := coalesce(
    nullif(trim(m->>'nome'), ''),
    nullif(trim(m->>'full_name'), ''),
    nullif(trim(m->>'name'), ''),
    split_part(new.email, '@', 1)
  );

  foto_achada := coalesce(
    nullif(m->>'avatar_url', ''),
    nullif(m->>'picture', '')
  );

  insert into public.perfis (id, nome, telefone, cpf, foto_url)
  values (
    new.id,
    nome_achado,
    coalesce(nullif(m->>'telefone', ''), nullif(m->>'phone', '')),
    nullif(n, ''),
    foto_achada
  )
  on conflict (id) do nothing;

  update public.barbeiros
  set perfil_id = new.id
  where perfil_id is null
    and email is not null
    and lower(email) = lower(new.email);

  if exists (select 1 from public.barbeiros where perfil_id = new.id) then
    update public.perfis set papel = 'barbeiro'
    where id = new.id and papel = 'cliente';
  end if;

  return new;
end $$;

-- ------------------------------------------------------------
-- 3. Saber se a conta está completa
-- Usado pelo site para pedir o CPF de quem entrou pelo Google.
-- ------------------------------------------------------------
create or replace function public.meu_cadastro_completo()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select cpf is not null from perfis where id = auth.uid()), false)
$$;

grant execute on function public.meu_cadastro_completo to authenticated;

-- ------------------------------------------------------------
-- 4. Achar a conta pelo CPF
-- Não é exposta ao site: só a Edge Function de login chama, com
-- a chave administrativa. Devolver o e-mail para qualquer um
-- seria entregar de graça quem é o dono de cada CPF.
-- ------------------------------------------------------------
create or replace function public.conta_por_cpf(p_cpf text)
returns uuid language sql stable security definer set search_path = public as $$
  select id from perfis
  where cpf = regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g')
  limit 1
$$;

revoke all on function public.conta_por_cpf(text) from public, anon, authenticated;
