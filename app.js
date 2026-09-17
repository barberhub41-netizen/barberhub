// ============================================================
// BarberHub — funções compartilhadas pelas páginas
// ============================================================
import { sb } from './config.js';

export { sb };

// ------------------------------------------------------------
// Sessão
// ------------------------------------------------------------
export async function sessaoAtual() {
  const { data: { session } } = await sb.auth.getSession();
  return session;
}

// Usar no topo das páginas que exigem login.
// Devolve a sessão, ou manda para o login e interrompe.
export async function exigirLogin() {
  const sessao = await sessaoAtual();
  if (!sessao) {
    location.replace('entrar.html');
    throw new Error('sem sessao');
  }
  return sessao;
}

export async function meuPerfil(sessao) {
  const { data } = await sb
    .from('perfis')
    .select('id, nome, telefone, papel')
    .eq('id', sessao.user.id)
    .maybeSingle();
  return data;
}

// ------------------------------------------------------------
// Topo compartilhado
// Cada página tem <header class="top" id="topo"></header>
// ------------------------------------------------------------
const TESOURA = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><line x1="20" y1="4" x2="8.1" y2="15.9"/><line x1="14.5" y1="14.5" x2="20" y2="20"/><line x1="8.1" y1="8.1" x2="12" y2="12"/></svg>';

export async function montarTopo(atual = '') {
  const topo = document.getElementById('topo');
  if (!topo) return;

  const sessao = await sessaoAtual();
  const marca = (p) => atual === p ? ' class="on"' : '';

  let direita;
  if (sessao) {
    const perfil = await meuPerfil(sessao);
    const nome = (perfil?.nome || sessao.user.email).split(' ')[0];
    direita =
      '<a class="btn btn-outline btn-sm" href="meus-agendamentos.html">Meus agendamentos</a>' +
      '<button class="btn btn-solid btn-sm" id="sair">Sair, ' + escapar(nome) + '</button>';
  } else {
    direita =
      '<a class="btn btn-outline btn-sm" href="entrar.html">Entrar</a>' +
      '<a class="btn btn-solid btn-sm" href="cadastro.html">Criar conta</a>';
  }

  topo.innerHTML =
    '<div class="wrap top-in">' +
      '<a class="logo" href="index.html"><span class="logo-mark">' + TESOURA + '</span>' +
      '<span><b>Barber<i>Hub</i></b><small>Para todos os estilos</small></span></a>' +
      '<nav class="menu">' +
        '<a href="buscar.html"' + marca('buscar') + '>Barbearias</a>' +
        '<a href="para-estabelecimentos.html"' + marca('estabelecimento') + '>Sou estabelecimento</a>' +
      '</nav>' +
      '<div class="top-cta">' + direita + '</div>' +
    '</div>';

  const sair = document.getElementById('sair');
  if (sair) {
    sair.addEventListener('click', async () => {
      await sb.auth.signOut();
      location.href = 'index.html';
    });
  }
}

// ------------------------------------------------------------
// Formatação
// ------------------------------------------------------------
export function moeda(centavos) {
  return (Number(centavos || 0) / 100).toLocaleString('pt-BR', {
    style: 'currency', currency: 'BRL'
  });
}

export function duracao(minutos) {
  const m = Number(minutos || 0);
  if (m < 60) return m + ' min';
  const h = Math.floor(m / 60), r = m % 60;
  return r ? h + 'h' + String(r).padStart(2, '0') : h + 'h';
}

export function quando(iso) {
  const d = new Date(iso);
  return d.toLocaleString('pt-BR', {
    weekday: 'short', day: '2-digit', month: 'short',
    hour: '2-digit', minute: '2-digit'
  });
}

// Evita que um nome com < ou > quebre o HTML da página.
export function escapar(texto = '') {
  return String(texto)
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

export function apelido(nome = '') {
  return nome.toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
}

// ------------------------------------------------------------
// Menu do painel do estabelecimento
// ------------------------------------------------------------
export function subnav(atual) {
  const itens = [
    ['agenda.html',          'Agenda'],
    ['estabelecimento.html', 'Dados'],
    ['servicos.html',        'Serviços'],
    ['barbeiros.html',       'Equipe'],
    ['jornadas.html',        'Horários'],
    ['fotos.html',           'Fotos'],
    ['planos.html',          'Planos'],
    ['avaliacoes.html',      'Avaliações'],
    ['clientes.html',        'Clientes'],
    ['relatorios.html',      'Relatórios']
  ];
  return '<nav class="subnav">' + itens.map(([href, nome]) =>
    '<a href="' + href + '"' + (href === atual ? ' class="on"' : '') + '>' + nome + '</a>'
  ).join('') + '</nav>';
}

// Todas as unidades do usuário logado: matriz primeiro, filiais depois.
export async function minhasBarbearias(sessao) {
  const { data } = await sb
    .from('estabelecimentos')
    .select('id, nome, apelido_unidade, matriz_id, slug, cidade, status, intervalo_min, logo_caminho')
    .eq('dono_id', sessao.user.id)
    .order('matriz_id', { nullsFirst: true })
    .order('nome');
  return data || [];
}

const CHAVE_UNIDADE = 'barberhub:unidade';

// A unidade que o painel está mostrando agora.
export async function minhaBarbearia(sessao) {
  const lista = await minhasBarbearias(sessao);
  if (!lista.length) return null;
  let escolhida = null;
  try {
    const guardada = localStorage.getItem(CHAVE_UNIDADE);
    escolhida = lista.find(b => b.id === guardada) || null;
  } catch (e) { /* navegador sem storage */ }
  return escolhida || lista[0];
}

export function nomeUnidade(b) {
  return b.apelido_unidade || (b.matriz_id ? b.cidade || 'Filial' : 'Unidade principal');
}

// Monta o menu do painel e o seletor de unidade. Devolve a unidade ativa.
export async function montarPainel(atual) {
  const sessao = await sessaoAtual();
  const lista = await minhasBarbearias(sessao);
  const ativa = await minhaBarbearia(sessao);
  const alvo = document.getElementById('menu');

  let seletor = '';
  if (lista.length > 1) {
    seletor = '<div class="unidades"><label for="troca-unidade">Unidade</label>' +
      '<select id="troca-unidade" class="entrada-data">' +
      lista.map(b => '<option value="' + b.id + '"' + (ativa && b.id === ativa.id ? ' selected' : '') + '>' +
        escapar(b.nome) + ' — ' + escapar(nomeUnidade(b)) + '</option>').join('') +
      '</select></div>';
  }

  if (alvo) alvo.innerHTML = subnav(atual) + seletor;

  const troca = document.getElementById('troca-unidade');
  if (troca) {
    troca.addEventListener('change', () => {
      try { localStorage.setItem(CHAVE_UNIDADE, troca.value); } catch (e) { /* ignora */ }
      location.reload();
    });
  }

  return ativa;
}

// Converte "45,00" ou "45" em 4500 centavos. Devolve null se não der.
export function paraCentavos(texto = '') {
  const limpo = String(texto).replace(/[^\d,.-]/g, '').replace(/\./g, '').replace(',', '.');
  const n = Number(limpo);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) : null;
}

export function deCentavos(centavos) {
  return (Number(centavos || 0) / 100).toFixed(2).replace('.', ',');
}

// ------------------------------------------------------------
// Imagens guardadas no Storage
// Guardamos só o caminho no banco; a URL é montada aqui.
// ------------------------------------------------------------
export const BUCKET = 'estabelecimentos';

export function urlImagem(caminho) {
  if (!caminho) return null;
  return sb.storage.from(BUCKET).getPublicUrl(caminho).data.publicUrl;
}

// Valida antes de enviar, para o erro aparecer na hora certa.
export function conferirImagem(arquivo, limiteMb = 5) {
  const tipos = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
  if (!arquivo) return 'Escolha um arquivo.';
  if (!tipos.includes(arquivo.type)) return 'Formato não aceito. Use JPG, PNG, WEBP ou GIF.';
  if (arquivo.size > limiteMb * 1024 * 1024) return 'A imagem passa de ' + limiteMb + ' MB. Reduza antes de enviar.';
  return null;
}

export function extensaoDe(arquivo) {
  const mapa = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif' };
  return mapa[arquivo.type] || 'jpg';
}

// ------------------------------------------------------------
// Estrelas
// ------------------------------------------------------------
export function estrelas(nota, tamanho = '') {
  const n = Math.round(Number(nota) || 0);
  let saida = '<span class="estrelas' + (tamanho ? ' ' + tamanho : '') + '">';
  for (let i = 1; i <= 5; i++) saida += '<i' + (i <= n ? ' class="cheia"' : '') + '>★</i>';
  return saida + '</span>';
}

export const PERIODOS = {
  mensal:     { nome: 'Mensal',     porMes: 1,  dias: 30 },
  trimestral: { nome: 'Trimestral', porMes: 3,  dias: 90 },
  semestral:  { nome: 'Semestral',  porMes: 6,  dias: 180 },
  anual:      { nome: 'Anual',      porMes: 12, dias: 365 }
};

// ============================================================
// Assinaturas: ciclo atual, cota e preço com plano
// ============================================================

// Devolve o ciclo vigente da assinatura, andando de período em
// período desde o início até alcançar hoje.
export function cicloAtual(assinatura, periodicidade) {
  const dias = PERIODOS[periodicidade]?.dias || 30;
  const inicio = new Date(assinatura.inicio + 'T00:00:00');
  const agora = new Date();
  let de = new Date(inicio);
  let ate = new Date(de.getTime() + dias * 86400000);
  let guarda = 0;
  while (ate <= agora && guarda++ < 500) {
    de = ate;
    ate = new Date(de.getTime() + dias * 86400000);
  }
  return { de, ate };
}

// A assinatura ativa do cliente naquele estabelecimento, com o
// plano, os itens e quanto já foi usado no ciclo.
export async function assinaturaDoCliente(clienteId, estabelecimentoId) {
  const hoje = new Date().toISOString().slice(0, 10);

  const { data } = await sb.from('assinaturas')
    .select('id, inicio, fim, status, planos(id, nome, periodicidade, usos_por_periodo, desconto_servicos_pct, desconto_produtos_pct)')
    .eq('cliente_id', clienteId)
    .eq('estabelecimento_id', estabelecimentoId)
    .eq('status', 'ativa')
    .order('inicio', { ascending: false })
    .limit(1);

  const assinatura = (data || [])[0];
  if (!assinatura || !assinatura.planos) return null;
  if (assinatura.fim && assinatura.fim < hoje) return null;

  const { de, ate } = cicloAtual(assinatura, assinatura.planos.periodicidade);

  const [itens, consumo] = await Promise.all([
    sb.from('plano_itens')
      .select('servico_id, quantidade, desconto_excedente_pct')
      .eq('plano_id', assinatura.planos.id),
    sb.rpc('consumo_assinatura', {
      p_assinatura: assinatura.id,
      p_de: de.toISOString(),
      p_ate: ate.toISOString()
    })
  ]);

  const usados = new Map((consumo.data || []).map(u => [u.servico_id, Number(u.usados)]));
  const totalUsado = [...usados.values()].reduce((t, n) => t + n, 0);

  return {
    id: assinatura.id,
    plano: assinatura.planos,
    ciclo: { de, ate },
    itens: itens.data || [],
    usados,
    totalUsado
  };
}

// Como cada serviço escolhido seria cobrado com esse plano.
// Devolve, na ordem recebida, o preço final e o motivo.
export function aplicarPlano(servicos, assinatura) {
  if (!assinatura) {
    return servicos.map(s => ({
      servico: s, coberto: false, desconto: 0,
      preco: s.preco_centavos, motivo: ''
    }));
  }

  const { plano, itens, usados, totalUsado } = assinatura;
  const restaGeral = plano.usos_por_periodo == null
    ? Infinity
    : Math.max(0, plano.usos_por_periodo - totalUsado);

  const jaUsados = new Map(usados);
  let gastosGerais = 0;

  return servicos.map(s => {
    const regra = itens.find(i => i.servico_id === s.id);

    // serviço fora do plano: desconto geral, se houver
    if (!regra) {
      const pct = Number(plano.desconto_servicos_pct) || 0;
      return {
        servico: s, coberto: false, desconto: pct,
        preco: Math.round(s.preco_centavos * (1 - pct / 100)),
        motivo: pct ? pct + '% de desconto do plano' : ''
      };
    }

    const usadosDoServico = jaUsados.get(s.id) || 0;
    const cota = regra.quantidade == null ? Infinity : regra.quantidade;
    const cabe = usadosDoServico < cota && (restaGeral - gastosGerais) > 0;

    if (cabe) {
      jaUsados.set(s.id, usadosDoServico + 1);
      gastosGerais++;
      const restante = cota === Infinity ? null : cota - usadosDoServico - 1;
      return {
        servico: s, coberto: true, desconto: 100, preco: 0,
        motivo: cota === Infinity
          ? 'incluído no plano'
          : 'incluído no plano · restam ' + restante + ' no ciclo'
      };
    }

    // cota esgotada: vale o desconto de excedente
    const pct = Number(regra.desconto_excedente_pct) || 0;
    return {
      servico: s, coberto: false, desconto: pct,
      preco: Math.round(s.preco_centavos * (1 - pct / 100)),
      motivo: pct ? 'cota usada · ' + pct + '% de desconto' : 'cota do ciclo já usada'
    };
  });
}
