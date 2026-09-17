-- ============================================================
-- BarberHub — migração 04
-- Logo e fotos do estabelecimento.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Onde os arquivos ficam
-- Bucket público: as imagens são vistas por qualquer visitante,
-- que é o esperado para logo e fotos de vitrine.
-- Limite de 5 MB por arquivo, só imagem.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'estabelecimentos', 'estabelecimentos', true, 5242880,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

-- ------------------------------------------------------------
-- 2. Quem pode mexer nos arquivos
-- Convenção de caminho:  <id-do-estabelecimento>/<arquivo>
-- Assim a primeira pasta diz de quem é o arquivo.
-- ------------------------------------------------------------
drop policy if exists estab_imagens_ler on storage.objects;
create policy estab_imagens_ler on storage.objects for select to anon, authenticated
using (bucket_id = 'estabelecimentos');

drop policy if exists estab_imagens_enviar on storage.objects;
create policy estab_imagens_enviar on storage.objects for insert to authenticated
with check (
  bucket_id = 'estabelecimentos'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
  and public.gerencio_estab(((storage.foldername(name))[1])::uuid)
);

drop policy if exists estab_imagens_trocar on storage.objects;
create policy estab_imagens_trocar on storage.objects for update to authenticated
using (
  bucket_id = 'estabelecimentos'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
  and public.gerencio_estab(((storage.foldername(name))[1])::uuid)
);

drop policy if exists estab_imagens_apagar on storage.objects;
create policy estab_imagens_apagar on storage.objects for delete to authenticated
using (
  bucket_id = 'estabelecimentos'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
  and public.gerencio_estab(((storage.foldername(name))[1])::uuid)
);

-- ------------------------------------------------------------
-- 3. A logo fica no próprio estabelecimento
-- Guardamos o caminho dentro do bucket, não a URL inteira:
-- se um dia o endereço do projeto mudar, nada quebra.
-- ------------------------------------------------------------
alter table estabelecimentos
  add column if not exists logo_caminho text;

-- ------------------------------------------------------------
-- 4. As fotos da vitrine, em ordem
-- ------------------------------------------------------------
create table if not exists fotos (
  id                  uuid primary key default gen_random_uuid(),
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  caminho             text not null,
  legenda             text,
  ordem               smallint not null default 0,
  criado_em           timestamptz not null default now()
);

create index if not exists idx_fotos_estab on fotos (estabelecimento_id, ordem);

alter table fotos enable row level security;

drop policy if exists fotos_ler on fotos;
create policy fotos_ler on fotos for select to anon, authenticated
using (
  public.estab_disponivel(estabelecimento_id)
  or public.gerencio_estab(estabelecimento_id)
);

drop policy if exists fotos_gerir on fotos;
create policy fotos_gerir on fotos for all to authenticated
using (public.gerencio_estab(estabelecimento_id))
with check (public.gerencio_estab(estabelecimento_id));
