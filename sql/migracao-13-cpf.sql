-- ============================================================
-- BarberHub — migração 13
-- CPF na conta de pessoa, um por CPF.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Conferência dos dígitos
-- Não prova que o CPF existe na Receita, mas descarta digitação
-- errada e número inventado.
-- ------------------------------------------------------------
create or replace function public.cpf_valido(p_cpf text)
returns boolean language plpgsql immutable as $$
declare
  n text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  soma integer;
  resto integer;
  i integer;
begin
  if length(n) <> 11 then return false; end if;

  -- 11111111111, 22222222222 e afins não valem
  if n ~ '^(\d)\1{10}$' then return false; end if;

  soma := 0;
  for i in 1..9 loop
    soma := soma + substr(n, i, 1)::integer * (11 - i);
  end loop;
  resto := (soma * 10) % 11;
  if resto = 10 then resto := 0; end if;
  if resto <> substr(n, 10, 1)::integer then return false; end if;

  soma := 0;
  for i in 1..10 loop
    soma := soma + substr(n, i, 1)::integer * (12 - i);
  end loop;
  resto := (soma * 10) % 11;
  if resto = 10 then resto := 0; end if;
  if resto <> substr(n, 11, 1)::integer then return false; end if;

  return true;
end $$;

grant execute on function public.cpf_valido to anon, authenticated;

-- ------------------------------------------------------------
-- 2. A coluna
-- Guardado só com dígitos, para não haver 000.000.000-00 e
-- 00000000000 convivendo como se fossem diferentes.
-- Fica nulo nas contas que já existiam.
-- ------------------------------------------------------------
alter table perfis
  add column if not exists cpf text;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'perfis_cpf_valido' and conrelid = 'public.perfis'::regclass
  ) then
    alter table perfis
      add constraint perfis_cpf_valido
      check (cpf is null or (cpf ~ '^\d{11}$' and public.cpf_valido(cpf)));
  end if;
end $$;

-- uma conta por CPF
create unique index if not exists idx_perfis_cpf on perfis (cpf) where cpf is not null;

-- ------------------------------------------------------------
-- 3. Conferir antes de tentar criar a conta
-- Devolve só sim ou não: ninguém descobre de quem é o CPF.
-- ------------------------------------------------------------
create or replace function public.cpf_disponivel(p_cpf text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  n text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
begin
  if not public.cpf_valido(n) then
    return jsonb_build_object('ok', false, 'motivo', 'Esse CPF não é válido. Confira os números.');
  end if;

  if exists (select 1 from perfis where cpf = n) then
    return jsonb_build_object('ok', false, 'motivo', 'Já existe uma conta com esse CPF.');
  end if;

  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.cpf_disponivel to anon, authenticated;

-- ------------------------------------------------------------
-- 4. O cadastro passa a gravar o CPF
-- Se vier repetido, o índice recusa e a conta não é criada.
-- ------------------------------------------------------------
create or replace function public.criar_perfil_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n text := regexp_replace(coalesce(new.raw_user_meta_data->>'cpf', ''), '\D', '', 'g');
begin
  insert into public.perfis (id, nome, telefone, cpf)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'telefone',
    nullif(n, '')
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
-- 5. O CPF não se troca sozinho
-- Depois de gravado, só admin altera.
-- ------------------------------------------------------------
create or replace function public.protege_cpf()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.cpf is not null and new.cpf is distinct from old.cpf and not public.e_admin() then
    new.cpf := old.cpf;
  end if;
  return new;
end $$;

drop trigger if exists perfis_protege_cpf on perfis;
create trigger perfis_protege_cpf
  before update on perfis
  for each row execute function public.protege_cpf();
