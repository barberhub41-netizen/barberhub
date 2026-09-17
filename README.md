# BarberHub

Plataforma de agendamento para barbearias e seus clientes.

Site estático (HTML, CSS e JavaScript) com banco de dados e autenticação no Supabase.

---

## Estrutura

```
index.html                 início — página do cliente
buscar.html                lista as barbearias disponíveis no catálogo
barbearia.html             perfil de uma barbearia  (ainda não existe)
entrar.html                login por e-mail/senha e Google
cadastro.html              criação de conta de cliente
meus-agendamentos.html     agendamentos do cliente, com cancelamento
estabelecimento.html       cadastro e edição da barbearia
app.js                     funções compartilhadas (sessão, topo, formatação)
config.js                  conexão com o Supabase
estilo.css                 estilo compartilhado por todas as páginas
sql/schema.sql             tabelas, índices e gatilhos
sql/permissoes.sql         políticas de RLS (quem vê e edita o quê)
sql/conferencia.sql        consulta que confere se o banco está completo
```

---

## Como rodar localmente

Os arquivos usam módulos JavaScript, que o navegador bloqueia quando a página
é aberta direto do disco (`file://`). É preciso servir por um servidor:

```bash
cd barberhub
python -m http.server 3000
```

Depois acesse `http://localhost:3000`.

---

## Publicação pelo GitHub Pages

Settings → Pages → Source: **Deploy from a branch** → Branch `main`, pasta `/ (root)`.

O endereço publicado precisa estar cadastrado no Supabase em
**Authentication → URL Configuration**, tanto em *Site URL* quanto em
*Redirect URLs* (com `/**` no final).

---

## Banco de dados

Os arquivos da pasta `sql/` são executados no **SQL Editor** do Supabase,
nesta ordem:

1. `schema.sql` — cria as tabelas
2. `permissoes.sql` — cria as regras de acesso
3. `conferencia.sql` — confere; deve retornar 8 linhas

Todos podem ser executados mais de uma vez sem duplicar nada.

### Tabelas

| Tabela | Guarda |
|---|---|
| `perfis` | nome, telefone e papel de cada usuário |
| `estabelecimentos` | dados da barbearia e o status no catálogo |
| `barbeiros` | equipe de cada estabelecimento |
| `servicos` | nome, preço em centavos e duração |
| `jornadas` | horário de trabalho por barbeiro e dia da semana |
| `agendamentos` | quem, com quem, quando e em que status |

Decisões que valem lembrar:

- **Preço em centavos** (inteiro), para não haver erro de arredondamento.
- **Horário em `timestamptz`**, guardado em UTC e convertido só na tela.
- **O banco recusa horário duplo**: a restrição `agendamentos_sem_conflito`
  impede dois atendimentos sobrepostos no mesmo barbeiro.
- **Agendamento não se apaga**, cancela — o status vira `cancelado`.
- **Catálogo aberto**: quem não está logado vê os estabelecimentos com status
  `disponivel`. Em `rascunho`, só o dono enxerga.

---

## Sobre a chave no `config.js`

A chave `anon` fica visível no navegador de qualquer visitante. É assim por
projeto: quem protege os dados são as políticas de RLS. Pode ficar no
repositório público sem problema.

A chave **service_role** nunca deve entrar aqui, nem em qualquer arquivo do
site. Ela ignora o RLS e dá acesso total ao banco.

---

## Roadmap

- [x] 1. Banco de dados real
- [x] 2. Login e perfis de acesso
- [x] 3. Cadastro do estabelecimento *(dados básicos; faltam redes sociais e pagamento)*
- [ ] 4. Upload de logo e fotos
- [ ] 5. Perfil individual da barbearia
- [x] 6. Disponibilização no catálogo *(rascunho / disponível)*
- [x] 7. Busca real *(falta filtro por serviço e distância)*
- [ ] 8. Agenda
- [ ] 9. Agendamento do cliente
- [ ] 10. Painel do estabelecimento
- [ ] 11. Funcionalidades de gestão
- [ ] 12. Aplicativo instalável
- [ ] 13. Testes completos
- [ ] 14. Pagamentos
- [ ] 15. Publicação

Pagamento e publicação ficam bloqueados até que cadastros, perfis, agenda,
permissões, gestão e testes estejam prontos.
