// ============================================================
// BarberHub — conexão com o Supabase
// ============================================================
// Preencha os dois valores abaixo com os dados do SEU projeto.
// No painel: Project Settings -> API
//   - Project URL          -> SUPABASE_URL
//   - Project API keys -> anon / public  -> SUPABASE_ANON_KEY
//
// A chave "anon" é pública por natureza: ela fica visível no
// navegador de qualquer visitante, e é assim mesmo. Quem protege
// os dados são as políticas de RLS que já criamos no banco.
//
// NUNCA coloque aqui a chave "service_role". Essa ignora o RLS
// e daria acesso total à base para qualquer pessoa.
// ============================================================

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

export const SUPABASE_URL = 'https://njjbghdhjeotatwsoxke.supabase.co';
export const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5qamJnaGRoamVvdGF0d3NveGtlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk2NTM4NTgsImV4cCI6MjEwNTIyOTg1OH0.RXhxYSX5PixsGuqbqKKJ1o3rZLBrHx8lbh2wgc-9jFA';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Chave PÚBLICA do push. Pode ficar aqui: ela é feita para
// aparecer no navegador. A privada fica só nos segredos da
// Edge Function, no painel do Supabase.
export const VAPID_PUBLICA = 'BGiPaXnap1b2N5VwqXdJoxP9tCVTDMx9fu9zq5-ceKe2WSekPQqwy8_we33ruEiQ3iOmVD-F3xbwpXpuv78Ma3s';

// Traduz as mensagens de erro do Supabase, que vêm em inglês.
export function traduzErro(mensagem = '') {
  const m = mensagem.toLowerCase();
  if (m.includes('invalid login credentials')) return 'E-mail ou senha incorretos.';
  if (m.includes('user already registered')) return 'Já existe uma conta com esse e-mail.';
  if (m.includes('password should be at least')) return 'A senha precisa ter pelo menos 6 caracteres.';
  if (m.includes('unable to validate email')) return 'Esse e-mail não parece válido.';
  if (m.includes('email rate limit')) return 'Muitas tentativas. Aguarde alguns minutos.';
  if (m.includes('failed to fetch')) return 'Não foi possível falar com o servidor. Confira a URL e a chave no config.js.';
  return mensagem || 'Não foi possível concluir. Tente de novo.';
}
