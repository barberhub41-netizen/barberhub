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
comandas.html              comandas do dia, itens e fechamento
produtos.html              produtos e controle de estoque
promocoes.html             cupons, aniversariantes e clientes sumidos
minha-agenda.html          agenda do barbeiro funcionário
planos.html                planos de assinatura, assinantes e fidelidade
clientes.html              clientes da barbearia, consolidados
relatorios.html            faturamento, faltas e quebras por período
agenda.html                agenda do dia em calendário, com encaixe
servicos.html              cadastro de serviços do estabelecimento
barbeiros.html             cadastro da equipe
entrar.html                login por e-mail/senha ou CPF/senha
recuperar.html             pedido do link de nova senha
nova-senha.html            definição da nova senha
completar.html             completa o cadastro de quem entrou pelo Google
perfil.html                perfil do cliente e favoritas
cadastro.html              criação de conta de cliente (nome, CPF, e-mail, senha)
criar-conta.html           escolha entre conta de cliente e de estabelecimento
cadastro-estabelecimento.html  conta e barbearia numa tela só
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
sql/migracao-07-perfil-favoritos.sql  perfil do cliente, foto, favoritos
sql/migracao-08-comandas-comissoes.sql  produtos, estoque, comandas, comissões
sql/migracao-09-notificacoes.sql  avisos no sino do topo
sql/migracao-10-push.sql       inscrições e disparo do push
sql/migracao-11-cupons.sql     cupons de desconto
sql/migracao-12-acesso-barbeiro.sql  login do profissional
sql/migracao-13-cpf.sql        CPF obrigatório, um por conta
sql/migracao-14-google-cpf.sql  dados do Google e login por CPF
sql/migracao-15-proteger-cpf.sql  fecha a leitura do CPF por coluna
sql/migracao-16-tempo-por-barbeiro.sql  tempo e serviços por profissional
sw.js                          service worker: push e cache básico
manifest.json                  torna o site instalável
supabase/functions/enviar-push/index.ts     Edge Function que entrega o push
supabase/functions/criar-barbeiro/index.ts  cria o login do profissional
supabase/functions/entrar-cpf/index.ts      login por CPF e senha
GERAR-CHAVES-VAPID.md          como gerar e onde guardar as chaves
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
| `barbeiro_servicos` | o que cada profissional faz, e em quanto tempo |
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
| `favoritos` | barbearias guardadas pelo cliente |
| `produtos` | o que a barbearia revende, com estoque |
| `movimentos_estoque` | entradas, saídas e ajustes |
| `comandas` | consumo do cliente e forma de pagamento |
| `comanda_itens` | itens da comanda, com comissão calculada |
| `notificacoes` | avisos internos, criados por gatilho |
| `push_assinaturas` | aparelhos inscritos para receber push |
| `cupons` | códigos de desconto |
| `cupom_usos` | quem usou qual cupom |

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
- **O caixa sai das comandas**, não dos agendamentos. Um atendimento
  concluído sem comanda não entra no faturamento nem gera comissão — o
  relatório avisa quantos estão nessa situação.
- **O estoque baixa por gatilho** quando um produto entra numa comanda, e
  volta quando o item é removido.
- **Catálogo aberto**: quem não está logado vê os estabelecimentos com status
  `disponivel`. Em `rascunho`, só o dono enxerga.

---

## Aplicativo por barbearia

O GitHub Pages só serve arquivo pronto, então o manifesto de cada
estabelecimento é montado pelo **service worker**, que intercepta
`manifest.json?slug=...` e responde com o nome e a logo daquela barbearia.
O ícone também passa por ele (`icone-barbearia.png?u=...`), porque o
manifesto exige ícone da mesma origem da página.

No iPhone o caminho é outro: o iOS ignora o manifesto e usa a tag
`apple-touch-icon`, trocada pelo JavaScript ao abrir o perfil.

Para o ícone ficar bom, a logo cadastrada precisa ser quadrada e ter pelo
menos 512 pixels de lado. O Chrome recusa instalar com ícone menor que 144.

## CPF

O cadastro exige CPF, com conferência dos dígitos no navegador e no banco,
e há um índice único: **uma conta por CPF**. O número é guardado só com
dígitos, e um gatilho impede que seja trocado depois de gravado — só admin
altera.

Contas criadas antes desta regra ficam sem CPF e continuam funcionando. O
perfil oferece preencher uma vez.

### Quem consegue ler

Ninguém, direto. O privilégio de `select` **na coluna** `cpf` foi retirado de
`anon` e `authenticated`, então nem o dono da barbearia enxerga o CPF dos
clientes dele — mesmo tendo permissão de ler a linha para mostrar o nome na
agenda. RLS trabalha por linha; separar coluna exige tirar o privilégio.

O acesso acontece por duas funções:

- `meu_cpf()` — devolve o CPF de quem está logado
- `gravar_meu_cpf(cpf)` — grava uma vez, na própria conta

### Sobre guardar em hash

Hash simples de CPF não protege: existem cerca de 1,5 bilhão de números
válidos, e testar todos leva segundos. Só faria sentido com um segredo
guardado no Vault, e aí o número vira irrecuperável — o que conflita com o
passo 14, já que Pix e boleto exigem o CPF do pagador.

A senha não é assunto nosso: fica em `auth.users`, com bcrypt, gerenciada
pelo Supabase. Nem a chave administrativa lê.

Isso é dado pessoal. Quando for publicar (passo 15), ele precisa aparecer
na política de privacidade, com a finalidade declarada.

## Login com Google

Removido das telas por escolha: o Google Cloud pede cartão de crédito no
cadastro do projeto. O código de suporte continua no banco — a função
`criar_perfil_novo_usuario` já aproveita nome, e-mail e foto de qualquer
provedor, e `completar.html` pede só o CPF depois. Para reativar, basta
configurar o provedor no Supabase e devolver o botão às telas de acesso.

## Perfis de acesso

Existe **um cadastro só**: a conta de pessoa. O que muda é o vínculo.

| Situação | O que enxerga |
|---|---|
| Só tem conta | cliente: busca, agendamento, avaliação, favoritos |
| É `dono_id` de um estabelecimento | o painel inteiro daquela unidade |
| Tem `perfil_id` numa linha de `barbeiros` | `minha-agenda.html`: a própria agenda e a própria comissão |
| `perfis.papel = 'admin'` | tudo, pelas políticas de RLS |

Há dois caminhos de cadastro, que levam à mesma tabela de contas:
`cadastro.html` para quem vai marcar horário e
`cadastro-estabelecimento.html`, que cria a conta e a barbearia juntas.

O menu do topo muda conforme o papel: quem tem barbearia vê "Meu painel",
o profissional vê "Minha agenda", e o cliente vê "Tenho uma barbearia".

O dono cria o acesso do profissional em Equipe → Criar acesso, escolhendo
o e-mail e a senha. A Edge
Function `criar-barbeiro` cria a conta com uma senha temporária, mostrada
uma única vez. Se a pessoa já tiver conta, ela é apenas ligada ao perfil.

O barbeiro **não** vê faturamento, clientes, relatórios nem configurações —
só a agenda dele e a comissão dele. Isso é garantido pelas políticas de RLS,
não por esconder botão.

## Notificações

O sino do topo funciona sozinho, sem servidor: os gatilhos do banco criam
as linhas em `notificacoes` e o site lê.

O **push** precisa de duas coisas a mais, feitas uma vez pelo painel:

1. A Edge Function `enviar-push` publicada (Edge Functions → Deploy a new
   function → colar `supabase/functions/enviar-push/index.ts`)
2. As chaves cadastradas — veja `GERAR-CHAVES-VAPID.md`

Sem isso, o gatilho `disparar_push` não faz nada e o resto continua
funcionando normalmente.

No iPhone, o push só chega depois que a pessoa adiciona o site à tela de
início pelo Safari. É limitação da Apple, não do código.

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
- [x] 11. Funcionalidades de gestão *(lembrete automático por horário ainda depende de agendador)*
- [x] 12. Aplicativo instalável *(manifesto por barbearia montado pelo service worker)*
- [ ] 13. Testes completos
- [ ] 14. Pagamentos
- [ ] 15. Publicação

Pagamento e publicação ficam bloqueados até que cadastros, perfis, agenda,
permissões, gestão e testes estejam prontos.
