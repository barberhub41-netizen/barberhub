# BarberHub

Plataforma de agendamento para barbearias e seus clientes.

Site estático (HTML, CSS e JavaScript) com banco de dados e autenticação no Supabase.

---

## Estrutura

```
index.html                 início — página do cliente
buscar.html                lista as barbearias disponíveis no catálogo
para-estabelecimentos.html apresentação da plataforma para donos de barbearia
barbearia.html             perfil público de uma barbearia
agendar.html               marcação de horário pelo cliente
jornadas.html              jornada, pausas e bloqueios de cada barbeiro
fotos.html                 upload da logo e das fotos
avaliacoes.html            avaliações recebidas, com resposta
planos.html                planos de assinatura, assinantes e fidelidade
clientes.html              clientes da barbearia, consolidados
relatorios.html            faturamento, faltas e quebras por período
agenda.html                agenda do dia em calendário, com encaixe
servicos.html              cadastro de serviços do estabelecimento
barbeiros.html             cadastro da equipe
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
sql/migracao-01-intervalo.sql  intervalo entre horários (rodar uma vez)
sql/migracao-02-encaixe.sql    cliente sem conta, para encaixe (rodar uma vez)
sql/migracao-03-bloqueios.sql  almoço, pausa, folga e férias (rodar uma vez)
sql/migracao-04-imagens.sql    bucket, logo e fotos (rodar uma vez)
sql/migracao-05-filiais-servicos-avaliacoes.sql  filiais, vários serviços,
                               avaliações, planos e fidelidade (rodar uma vez)
sql/migracao-06-planos-configuraveis.sql  cota por serviço e descontos
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
4. as migrações `migracao-01` a `migracao-04`, em ordem

As migrações dependem das funções criadas em `permissoes.sql`, então esse
arquivo tem de rodar antes delas.

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
| `bloqueios` | almoço, pausa, folga, férias e feriado |
| `fotos` | fotos da vitrine, em ordem |
| `agendamento_servicos` | os serviços de cada atendimento, com preço fechado |
| `avaliacoes` | nota e comentário do cliente, com resposta da barbearia |
| `planos` | planos de assinatura da barbearia |
| `assinaturas` | quem assinou qual plano |
| `plano_itens` | o que cada plano cobre, serviço a serviço |
| `fidelidade` | regra do cartão de pontos |

Decisões que valem lembrar:

- **Preço em centavos** (inteiro), para não haver erro de arredondamento.
- **Horário em `timestamptz`**, guardado em UTC e convertido só na tela.
- **O banco recusa horário duplo**: a restrição `agendamentos_sem_conflito`
  impede dois atendimentos sobrepostos no mesmo barbeiro.
- **Agendamento não se apaga**, cancela — o status vira `cancelado`.
- **Preço e duração ficam congelados** em `agendamento_servicos` no momento da
  marcação: mudar a tabela de preços não reescreve o histórico.
- **Filial é um estabelecimento** com `matriz_id` apontando para a unidade
  principal. Cada uma tem endereço, equipe, serviços e agenda próprios.
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
- [x] 4. Upload de logo e fotos
- [x] 5. Perfil individual da barbearia *(falta o mapa)*
- [x] 6. Disponibilização no catálogo *(rascunho / disponível)*
- [x] 7. Busca real *(falta filtro por serviço e distância)*
- [x] 8. Agenda *(jornada, pausas, folgas e férias por barbeiro)*
- [x] 9. Agendamento do cliente *(marcar e cancelar; falta remarcar)*
- [x] 10. Painel do estabelecimento *(agenda, serviços, equipe, horários; faltam relatórios)*
- [~] 11. Funcionalidades de gestão *(clientes, relatórios, avaliações, planos e fidelidade; faltam lembretes, promoções, comandas, estoque e comissões)*
- [ ] 12. Aplicativo instalável
- [ ] 13. Testes completos
- [ ] 14. Pagamentos
- [ ] 15. Publicação

Pagamento e publicação ficam bloqueados até que cadastros, perfis, agenda,
permissões, gestão e testes estejam prontos.
