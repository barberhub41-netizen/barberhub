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
        '<a href="estabelecimento.html"' + marca('estabelecimento') + '>Sou estabelecimento</a>' +
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
