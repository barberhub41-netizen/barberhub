-- ============================================================
-- BarberHub — migração 07
-- Perfil do cliente, foto, favoritos e coordenadas.
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- ============================================================

-- ------------------------------------------------------------
-- 1. O perfil ganha aniversário e foto
-- ------------------------------------------------------------
alter table perfis
  add column if not exists data_nascimento date,
  add column if not exists foto_caminho text;

comment on column perfis.data_nascimento is
  'Usado para promoção de aniversário. Opcional.';

-- ------------------------------------------------------------
-- 2. Onde ficam as fotos de perfil
-- Cada pessoa só mexe na própria pasta, que é o id dela.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('perfis', 'perfis', true, 2097152,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists perfis_foto_ler on storage.objects;
create policy perfis_foto_ler on storage.objects for select to anon, authenticated
using (bucket_id = 'perfis');

drop policy if exists perfis_foto_enviar on storage.objects;
create policy perfis_foto_enviar on storage.objects for insert to authenticated
with check (
  bucket_id = 'perfis'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists perfis_foto_trocar on storage.objects;
create policy perfis_foto_trocar on storage.objects for update to authenticated
using (
  bucket_id = 'perfis'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists perfis_foto_apagar on storage.objects;
create policy perfis_foto_apagar on storage.objects for delete to authenticated
using (
  bucket_id = 'perfis'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- ------------------------------------------------------------
-- 3. Favoritos
-- ------------------------------------------------------------
create table if not exists favoritos (
  cliente_id          uuid not null references perfis(id) on delete cascade,
  estabelecimento_id  uuid not null references estabelecimentos(id) on delete cascade,
  criado_em           timestamptz not null default now(),
  primary key (cliente_id, estabelecimento_id)
);

create index if not exists idx_favoritos_cliente on favoritos (cliente_id);

alter table favoritos enable row level security;

drop policy if exists favoritos_meus on favoritos;
create policy favoritos_meus on favoritos for all to authenticated
using (cliente_id = auth.uid())
with check (cliente_id = auth.uid());

-- ------------------------------------------------------------
-- 4. Coordenadas do estabelecimento
-- As colunas já existiam; aqui só entra o índice para a busca
-- por proximidade não varrer a tabela inteira.
-- ------------------------------------------------------------
create index if not exists idx_estab_coordenadas
  on estabelecimentos (latitude, longitude)
  where status = 'disponivel' and latitude is not null;
