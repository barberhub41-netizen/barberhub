// ============================================================
// BarberHub — funções compartilhadas pelas páginas
// ============================================================
import { sb, VAPID_PUBLICA } from './config.js';

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
// Quem entrou pelo Google e ainda não tem CPF é levado antes
// para completar o cadastro.
export async function exigirLogin({ exigirCpf = true } = {}) {
  const sessao = await sessaoAtual();
  if (!sessao) {
    const aqui = location.pathname.split('/').pop() + location.search;
    location.replace('entrar.html?voltar=' + encodeURIComponent(aqui));
    throw new Error('sem sessao');
  }

  if (exigirCpf) {
    const { data: completo } = await sb.rpc('meu_cadastro_completo');
    if (completo === false) {
      const aqui = location.pathname.split('/').pop() + location.search;
      location.replace('completar.html?voltar=' + encodeURIComponent(aqui));
      throw new Error('cadastro incompleto');
    }
  }

  return sessao;
}

export async function meuPerfil(sessao) {
  const { data } = await sb
    .from('perfis')
    .select('id, nome, telefone, papel, foto_caminho, foto_url')
    .eq('id', sessao.user.id)
    .maybeSingle();
  return data;
}

// A foto que vale: a enviada pela pessoa, senão a do provedor.
export function fotoDoPerfil(perfil) {
  if (!perfil) return null;
  if (perfil.foto_caminho) return urlAvatar(perfil.foto_caminho);
  return perfil.foto_url || null;
}

// ------------------------------------------------------------
// Topo compartilhado
// Cada página tem <header class="top" id="topo"></header>
// ------------------------------------------------------------
const TESOURA = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><line x1="20" y1="4" x2="8.1" y2="15.9"/><line x1="14.5" y1="14.5" x2="20" y2="20"/><line x1="8.1" y1="8.1" x2="12" y2="12"/></svg>';

export async function montarTopo(atual = '', opcoes = {}) {
  const topo = document.getElementById('topo');
  if (!topo) return;

  const sessao = await sessaoAtual();
  const marca = (p) => atual === p ? ' class="on"' : '';

  let direita;
  let meuPapel = 'visitante';

  if (sessao) {
    const perfil = await meuPerfil(sessao);

    // dono de estabelecimento? barbeiro? cliente comum?
    const { data: minha } = await sb.from('estabelecimentos')
      .select('id')
      .eq('dono_id', sessao.user.id)
      .limit(1);

    meuPapel = (minha && minha.length) ? 'dono'
             : (perfil?.papel === 'barbeiro' ? 'barbeiro' : 'cliente');
    const nome = (perfil?.nome || sessao.user.email).split(' ')[0];
    direita =
      '<button class="sino" id="sino" aria-label="Avisos">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
        '<path d="M18 8a6 6 0 1 0-12 0c0 6-2.5 7-2.5 7h17S18 14 18 8z"/>' +
        '<path d="M10.3 20a2 2 0 0 0 3.4 0"/></svg>' +
        '<span class="contador" id="contador" hidden>0</span>' +
      '</button>' +
      (perfil?.papel === 'barbeiro'
        ? '<a class="btn btn-outline btn-sm" href="minha-agenda.html">Minha agenda</a>'
        : '<a class="btn btn-outline btn-sm" href="meus-agendamentos.html">Agendamentos</a>') +
      '<a class="btn btn-solid btn-sm" href="perfil.html">' + escapar(nome) + '</a>';
  } else if (opcoes.contexto === 'estabelecimento') {
    // área de quem tem barbearia: o convite é cadastrar o estabelecimento
    direita =
      '<a class="btn btn-outline btn-sm" href="entrar.html">Entrar</a>' +
      '<a class="btn btn-solid btn-sm" href="cadastro-estabelecimento.html">Criar estabelecimento</a>';
  } else {
    direita =
      '<a class="btn btn-outline btn-sm" href="entrar.html">Entrar</a>' +
      '<a class="btn btn-solid btn-sm" href="criar-conta.html">Criar conta</a>';
  }

  // na área do estabelecimento não faz sentido oferecer o catálogo
  const menu = (opcoes.contexto === 'estabelecimento' && meuPapel === 'visitante')
    ? '<a href="para-estabelecimentos.html"' + marca('estabelecimento') + '>Como funciona</a>' +
      '<a href="index.html">Sou cliente</a>'
    : null;

  // o segundo item do menu muda conforme o papel
  const segundoItem =
    meuPapel === 'dono'     ? '<a href="agenda.html"' + marca('estabelecimento') + '>Meu painel</a>'
  : meuPapel === 'barbeiro' ? '<a href="minha-agenda.html"' + marca('estabelecimento') + '>Minha agenda</a>'
  : meuPapel === 'cliente'  ? '<a href="cadastro-estabelecimento.html"' + marca('estabelecimento') + '>Tenho uma barbearia</a>'
  :                           '<a href="para-estabelecimentos.html"' + marca('estabelecimento') + '>Sou estabelecimento</a>';

  topo.innerHTML =
    '<div class="wrap top-in">' +
      '<a class="logo" href="index.html"><span class="logo-mark">' + TESOURA + '</span>' +
      '<span><b>Barber<i>Hub</i></b><small>Para todos os estilos</small></span></a>' +
      '<nav class="menu">' +
        (menu || ('<a href="buscar.html"' + marca('buscar') + '>Barbearias</a>' + segundoItem)) +
      '</nav>' +
      '<div class="top-cta">' + direita + '</div>' +
    '</div>';

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
    ['comandas.html',        'Comandas'],
    ['estabelecimento.html', 'Dados'],
    ['servicos.html',        'Serviços'],
    ['produtos.html',        'Produtos'],
    ['barbeiros.html',       'Equipe'],
    ['jornadas.html',        'Horários'],
    ['fotos.html',           'Fotos'],
    ['planos.html',          'Planos'],
    ['promocoes.html',       'Promoções'],
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
    .select('id, nome, apelido_unidade, matriz_id, slug, cidade, status, intervalo_min, logo_caminho, base_comissao')
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

// ============================================================
// Foto de perfil, favoritos, CEP e distância
// ============================================================
export const BUCKET_PERFIS = 'perfis';

export function urlAvatar(caminho) {
  if (!caminho) return null;
  return sb.storage.from(BUCKET_PERFIS).getPublicUrl(caminho).data.publicUrl;
}

// Distância em linha reta, em km. Suficiente para ordenar a busca.
export function distanciaKm(lat1, lon1, lat2, lon2) {
  if ([lat1, lon1, lat2, lon2].some(v => v == null)) return null;
  const R = 6371;
  const rad = (g) => (g * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function mostrarDistancia(km) {
  if (km == null) return '';
  return km < 1
    ? Math.round(km * 1000) + ' m'
    : km.toFixed(km < 10 ? 1 : 0).replace('.', ',') + ' km';
}

// Pede a posição ao navegador. Nunca rejeita: devolve null se
// a pessoa recusar ou o aparelho não souber.
export function ondeEstou(timeout = 8000) {
  return new Promise((resolve) => {
    if (!navigator.geolocation) return resolve(null);
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lon: p.coords.longitude }),
      () => resolve(null),
      { timeout, maximumAge: 300000 }
    );
  });
}

// Busca o endereço pelo CEP no ViaCEP. Devolve null se não achar.
export async function buscarCep(cep) {
  const limpo = String(cep).replace(/\D/g, '');
  if (limpo.length !== 8) return null;
  try {
    const r = await fetch('https://viacep.com.br/ws/' + limpo + '/json/');
    const d = await r.json();
    if (d.erro) return null;
    return {
      logradouro: d.logradouro || '',
      bairro: d.bairro || '',
      cidade: d.localidade || '',
      uf: d.uf || ''
    };
  } catch (e) {
    return null;
  }
}

export const PAGAMENTOS = {
  dinheiro: 'Dinheiro', pix: 'Pix', credito: 'Crédito',
  debito: 'Débito', plano: 'Plano/assinatura', cortesia: 'Cortesia', outro: 'Outro'
};

// Quanto de comissão cabe num item.
// base 'tabela' calcula sobre o preço cheio; 'cobrado', sobre o que
// o cliente pagou — muda o resultado quando há plano ou desconto.
export function calcularComissao({ pct, precoCheio, precoCobrado, base }) {
  const p = Number(pct) || 0;
  if (!p) return 0;
  const alvo = base === 'tabela' ? precoCheio : precoCobrado;
  return Math.round((alvo * p) / 100);
}


// ============================================================
// Aplicativo instalável e notificação push
// ============================================================

// Registra o service worker, que é quem recebe o push com o
// site fechado. Falha em silêncio se o navegador não suportar.
export async function ligarServiceWorker() {
  if (!('serviceWorker' in navigator)) return null;
  try {
    return await navigator.serviceWorker.register('./sw.js', { scope: './' });
  } catch (e) {
    console.warn('Service worker não registrou:', e);
    return null;
  }
}

export function pushDisponivel() {
  return 'serviceWorker' in navigator &&
         'PushManager' in window &&
         'Notification' in window &&
         VAPID_PUBLICA && !VAPID_PUBLICA.startsWith('COLE_AQUI');
}

// O navegador entrega a chave em base64url; a API quer bytes.
function chaveParaBytes(base64) {
  const preenchido = (base64 + '='.repeat((4 - base64.length % 4) % 4))
    .replace(/-/g, '+').replace(/_/g, '/');
  const cru = atob(preenchido);
  return Uint8Array.from([...cru].map(c => c.charCodeAt(0)));
}

function paraBase64(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

export async function estadoPush() {
  if (!pushDisponivel()) return 'indisponivel';
  if (Notification.permission === 'denied') return 'bloqueado';
  const reg = await navigator.serviceWorker.ready;
  const inscricao = await reg.pushManager.getSubscription();
  return inscricao ? 'ligado' : 'desligado';
}

export async function ativarPush(sessao) {
  if (!pushDisponivel()) throw new Error('Este navegador não aceita notificações.');

  const permissao = await Notification.requestPermission();
  if (permissao !== 'granted') {
    throw new Error('Você recusou as notificações. Para liberar, mude nas permissões do site.');
  }

  await ligarServiceWorker();
  const reg = await navigator.serviceWorker.ready;

  let inscricao = await reg.pushManager.getSubscription();
  if (!inscricao) {
    inscricao = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: chaveParaBytes(VAPID_PUBLICA)
    });
  }

  const dados = inscricao.toJSON();
  const { error } = await sb.from('push_assinaturas').upsert({
    perfil_id: sessao.user.id,
    endpoint: inscricao.endpoint,
    p256dh: dados.keys.p256dh,
    auth: dados.keys.auth,
    aparelho: navigator.userAgent.slice(0, 120)
  }, { onConflict: 'endpoint' });

  if (error) throw new Error('Não foi possível guardar a inscrição: ' + error.message);
  return true;
}

export async function desativarPush() {
  const reg = await navigator.serviceWorker.ready;
  const inscricao = await reg.pushManager.getSubscription();
  if (!inscricao) return;
  await sb.from('push_assinaturas').delete().eq('endpoint', inscricao.endpoint);
  await inscricao.unsubscribe();
}

// registra o service worker assim que a página carrega
ligarServiceWorker();

// ============================================================
// Adicionar ao calendário
// Google Agenda por link; iPhone e o resto por arquivo .ics,
// que é o formato que todo calendário entende.
// ============================================================

function carimbo(data) {
  return new Date(data).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

export function linkGoogleAgenda({ titulo, inicio, fim, local, descricao }) {
  const p = new URLSearchParams({
    action: 'TEMPLATE',
    text: titulo,
    dates: carimbo(inicio) + '/' + carimbo(fim),
    details: descricao || '',
    location: local || ''
  });
  return 'https://calendar.google.com/calendar/render?' + p.toString();
}

export function montarIcs({ titulo, inicio, fim, local, descricao, id }) {
  // o padrão exige quebra de linha CRLF e escape em vírgula e ponto e vírgula
  const limpar = (t = '') => String(t)
    .replace(/\\/g, '\\\\').replace(/;/g, '\\;')
    .replace(/,/g, '\\,').replace(/\n/g, '\\n');

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//BarberHub//PT-BR//',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:' + (id || Date.now()) + '@barberhub',
    'DTSTAMP:' + carimbo(new Date()),
    'DTSTART:' + carimbo(inicio),
    'DTEND:' + carimbo(fim),
    'SUMMARY:' + limpar(titulo),
    'DESCRIPTION:' + limpar(descricao),
    'LOCATION:' + limpar(local),
    'BEGIN:VALARM',
    'TRIGGER:-PT2H',
    'ACTION:DISPLAY',
    'DESCRIPTION:' + limpar(titulo),
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR'
  ].join('\r\n');
}

export function baixarIcs(evento, nomeArquivo = 'agendamento.ics') {
  const blob = new Blob([montarIcs(evento)], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nomeArquivo;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}


// ============================================================
// Instalar como aplicativo da barbearia
// No Android, quem manda é o manifesto — trocado aqui pelo da
// barbearia aberta. No iPhone, o que vale é o apple-touch-icon.
// ============================================================
let convitePendente = null;

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  convitePendente = e;
  document.dispatchEvent(new CustomEvent('barberhub:instalavel'));
});

export function podeInstalar() {
  return !!convitePendente;
}

export function jaInstalado() {
  return window.matchMedia('(display-mode: standalone)').matches ||
         window.navigator.standalone === true;
}

export function ehIphone() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent);
}

export async function pedirInstalacao() {
  if (!convitePendente) return false;
  convitePendente.prompt();
  const { outcome } = await convitePendente.userChoice;
  convitePendente = null;
  return outcome === 'accepted';
}

// Aponta o manifesto e o ícone do iPhone para esta barbearia.
export function manifestoDaBarbearia({ slug, nome, icone }) {
  const p = new URLSearchParams({ slug: slug || '', nome: nome || 'BarberHub' });
  if (icone) p.set('icone', icone);

  let link = document.querySelector('link[rel="manifest"]');
  if (!link) {
    link = document.createElement('link');
    link.rel = 'manifest';
    document.head.appendChild(link);
  }
  link.href = 'manifest.json?' + p.toString();

  if (icone) {
    document.querySelectorAll('link[rel="apple-touch-icon"]').forEach(l => l.remove());
    const ios = document.createElement('link');
    ios.rel = 'apple-touch-icon';
    ios.href = icone;
    document.head.appendChild(ios);
  }
}

// ============================================================
// CPF
// ============================================================
export function soDigitos(texto = '') {
  return String(texto).replace(/\D/g, '');
}

export function formatarCpf(texto = '') {
  const n = soDigitos(texto).slice(0, 11);
  return n
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d{1,2})$/, '.$1-$2');
}

// Mesma conferência que existe no banco, feita antes de enviar.
export function cpfValido(texto = '') {
  const n = soDigitos(texto);
  if (n.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(n)) return false;

  const digito = (ate) => {
    let soma = 0;
    for (let i = 0; i < ate; i++) soma += Number(n[i]) * (ate + 1 - i);
    const resto = (soma * 10) % 11;
    return resto === 10 ? 0 : resto;
  };

  return digito(9) === Number(n[9]) && digito(10) === Number(n[10]);
}

// Liga a máscara num campo de CPF.
export function mascaraCpf(campo) {
  if (!campo) return;
  campo.addEventListener('input', () => {
    const posicaoFinal = campo.selectionStart === campo.value.length;
    campo.value = formatarCpf(campo.value);
    if (posicaoFinal) campo.setSelectionRange(campo.value.length, campo.value.length);
  });
}
