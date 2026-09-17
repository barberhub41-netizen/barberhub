-- ============================================================
-- BarberHub — conferência do esquema
-- Rode no SQL Editor. Deve voltar 8 linhas, todas com "ok".
-- ============================================================

select 'tabela: ' || table_name as item, 'ok' as situacao
from information_schema.tables
where table_schema = 'public'
  and table_name in ('perfis','estabelecimentos','barbeiros','servicos','jornadas','agendamentos')

union all
select 'restricao: agendamentos_sem_conflito', 'ok'
from pg_constraint
where conname = 'agendamentos_sem_conflito'

union all
select 'gatilho: ao_criar_usuario', 'ok'
from pg_trigger
where tgname = 'ao_criar_usuario'

order by item;
