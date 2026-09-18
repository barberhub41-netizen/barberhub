-- ============================================================
-- BarberHub — migração 15
-- O CPF deixa de ser legível por quem não é o dono do dado.
--
-- O problema: a política de leitura de perfis permite o
-- estabelecimento ver o cliente que marcou com ele. Isso é
-- necessário para a agenda mostrar o nome, mas trazia o CPF
-- junto. RLS trabalha por linha; para separar coluna, o jeito
-- é tirar o privilégio da coluna.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Ninguém lê a coluna diretamente
-- As funções marcadas como security definer continuam lendo,
-- porque rodam com o dono da tabela.
-- ------------------------------------------------------------
revoke select (cpf) on public.perfis from anon, authenticated;
revoke update (cpf) on public.perfis from anon, authenticated;

-- ------------------------------------------------------------
-- 2. Ver o próprio CPF
-- ------------------------------------------------------------
create or replace function public.meu_cpf()
returns text language sql stable security definer set search_path = public as $$
  select cpf from perfis where id = auth.uid()
$$;

grant execute on function public.meu_cpf to authenticated;

-- ------------------------------------------------------------
-- 3. Gravar o CPF uma vez
-- Substitui o update direto, que acabou de perder o privilégio.
-- Só grava se ainda não havia, e só na própria conta.
-- ------------------------------------------------------------
create or replace function public.gravar_meu_cpf(p_cpf text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  atual text;
begin
  select cpf into atual from perfis where id = auth.uid();

  if atual is not null then
    return jsonb_build_object('ok', false, 'motivo', 'Seu CPF já está cadastrado e não muda.');
  end if;

  if not public.cpf_valido(n) then
    return jsonb_build_object('ok', false, 'motivo', 'Esse CPF não é válido. Confira os números.');
  end if;

  if exists (select 1 from perfis where cpf = n) then
    return jsonb_build_object('ok', false, 'motivo', 'Já existe uma conta com esse CPF.');
  end if;

  update perfis set cpf = n where id = auth.uid();

  return jsonb_build_object('ok', true);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'motivo', 'Já existe uma conta com esse CPF.');
end $$;

grant execute on function public.gravar_meu_cpf to authenticated;

-- ------------------------------------------------------------
-- 4. Conferir quem ainda consegue ler
-- Deve listar apenas o dono da tabela (postgres) e os papéis
-- de serviço. Se aparecer "authenticated", algo ficou aberto.
-- ------------------------------------------------------------
comment on column perfis.cpf is
  'Dado pessoal. Leitura só pelo próprio dono, via meu_cpf(). Nem o estabelecimento enxerga.';
