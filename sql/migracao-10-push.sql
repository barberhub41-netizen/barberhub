-- ============================================================
-- BarberHub — migração 10
-- Notificação push: guarda as inscrições dos aparelhos e
-- dispara a Edge Function sempre que nasce um aviso.
--
-- ANTES de rodar, leia o README: é preciso criar a função
-- "enviar-push" e guardar duas chaves no Vault.
-- ============================================================

-- pg_net faz o banco conseguir chamar uma URL
create extension if not exists pg_net;

-- ------------------------------------------------------------
-- 1. Um aparelho inscrito para receber push
-- A mesma pessoa pode ter vários: celular, notebook, tablet.
-- ------------------------------------------------------------
create table if not exists push_assinaturas (
  id          uuid primary key default gen_random_uuid(),
  perfil_id   uuid not null references perfis(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  aparelho    text,
  criado_em   timestamptz not null default now(),
  usado_em    timestamptz
);

create index if not exists idx_push_perfil on push_assinaturas (perfil_id);

alter table push_assinaturas enable row level security;

drop policy if exists push_minhas on push_assinaturas;
create policy push_minhas on push_assinaturas for all to authenticated
using (perfil_id = auth.uid())
with check (perfil_id = auth.uid());

-- ------------------------------------------------------------
-- 2. Onde ficam as chaves
-- Guardadas no Vault do Supabase, nunca no repositório.
-- Crie antes de rodar esta parte:
--
--   select vault.create_secret('https://SEU-PROJETO.supabase.co', 'url_projeto');
--   select vault.create_secret('SUA_SERVICE_ROLE_KEY', 'chave_servico');
--
-- ------------------------------------------------------------
create or replace function public.segredo(p_nome text)
returns text language sql stable security definer set search_path = vault, public as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_nome limit 1
$$;

revoke all on function public.segredo(text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. Todo aviso novo vira um push
-- A chamada é assíncrona: se a função falhar, o aviso continua
-- no sino normalmente.
-- ------------------------------------------------------------
create or replace function public.disparar_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  destino text := public.segredo('url_projeto');
  chave text := public.segredo('chave_servico');
begin
  if destino is null or chave is null then
    return new;   -- push não configurado ainda; segue sem erro
  end if;

  perform net.http_post(
    url := destino || '/functions/v1/enviar-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || chave
    ),
    body := jsonb_build_object(
      'perfil_id', new.destinatario_id,
      'titulo', new.titulo,
      'mensagem', coalesce(new.mensagem, ''),
      'link', coalesce(new.link, 'index.html'),
      'tipo', new.tipo
    )
  );

  return new;
end $$;

drop trigger if exists ao_criar_aviso on notificacoes;
create trigger ao_criar_aviso
  after insert on notificacoes
  for each row execute function public.disparar_push();

-- ------------------------------------------------------------
-- 4. Limpeza: inscrição que o navegador já descartou
-- A Edge Function apaga sozinha quando recebe 404 ou 410,
-- mas isso aqui serve de faxina manual.
-- ------------------------------------------------------------
create or replace function public.limpar_push_velhos(dias integer default 180)
returns integer language sql security definer set search_path = public as $$
  with mortas as (
    delete from push_assinaturas
    where coalesce(usado_em, criado_em) < now() - (dias || ' days')::interval
    returning 1
  )
  select count(*)::integer from mortas
$$;
