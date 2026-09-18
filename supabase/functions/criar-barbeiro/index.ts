// ============================================================
// BarberHub — Edge Function "criar-barbeiro"
// Cria a conta de acesso de um profissional, a pedido do dono
// do estabelecimento.
//
// Como publicar, pelo navegador:
//   Painel do Supabase → Edge Functions → Deploy a new function
//   Nome: criar-barbeiro
//   Cole este arquivo inteiro e publique.
//
// Não precisa cadastrar segredo nenhum: as duas variáveis usadas
// já vêm prontas em toda Edge Function.
// ============================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_PROJETO = Deno.env.get('SUPABASE_URL')!;
const CHAVE_ADMIN = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CHAVE_PUBLICA = Deno.env.get('SUPABASE_ANON_KEY')!;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

// Senha temporária legível: duas sílabas e quatro números.
function senhaTemporaria() {
  const partes = ['bar', 'cor', 'tes', 'lam', 'pen', 'nav', 'fio', 'tom'];
  const p = () => partes[Math.floor(Math.random() * partes.length)];
  const n = Math.floor(1000 + Math.random() * 9000);
  return p() + p() + n;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') {
    return new Response('Método não permitido', { status: 405, headers: CORS });
  }

  const responder = (corpo: unknown, status = 200) =>
    new Response(JSON.stringify(corpo), {
      status, headers: { ...CORS, 'Content-Type': 'application/json' }
    });

  try {
    const autorizacao = req.headers.get('Authorization') ?? '';
    if (!autorizacao) return responder({ erro: 'Sem autorização.' }, 401);

    const { barbeiro_id, email, nome } = await req.json();
    if (!barbeiro_id || !email) {
      return responder({ erro: 'Faltou barbeiro_id ou email.' }, 400);
    }

    // 1. Confere, usando o token de quem chamou, se essa pessoa
    //    realmente gerencia o estabelecimento daquele barbeiro.
    const comoUsuario = createClient(URL_PROJETO, CHAVE_PUBLICA, {
      global: { headers: { Authorization: autorizacao } }
    });

    const { data: barbeiro, error: erroBarbeiro } = await comoUsuario
      .from('barbeiros')
      .select('id, nome, estabelecimento_id, perfil_id')
      .eq('id', barbeiro_id)
      .maybeSingle();

    if (erroBarbeiro || !barbeiro) {
      return responder({ erro: 'Profissional não encontrado ou sem permissão.' }, 403);
    }

    if (barbeiro.perfil_id) {
      return responder({ erro: 'Esse profissional já tem acesso.' }, 409);
    }

    const { data: podeGerir } = await comoUsuario
      .rpc('gerencio_estab', { p_estab: barbeiro.estabelecimento_id });

    if (!podeGerir) {
      return responder({ erro: 'Só o dono do estabelecimento pode criar acesso.' }, 403);
    }

    // 2. Com a chave administrativa, cria a conta.
    const admin = createClient(URL_PROJETO, CHAVE_ADMIN);
    const limpo = String(email).trim().toLowerCase();
    const senha = senhaTemporaria();

    const { data: criado, error: erroCriar } = await admin.auth.admin.createUser({
      email: limpo,
      password: senha,
      email_confirm: true,
      user_metadata: { nome: nome || barbeiro.nome }
    });

    // Já existe conta com esse e-mail: em vez de erro, só amarra.
    if (erroCriar) {
      const jaExiste = /already|registered|exists/i.test(erroCriar.message);
      if (!jaExiste) return responder({ erro: erroCriar.message }, 400);

      const { data: ligou } = await comoUsuario
        .rpc('vincular_barbeiro', { p_barbeiro: barbeiro_id, p_email: limpo });

      if (ligou?.ok) {
        return responder({ ok: true, ja_tinha_conta: true });
      }
      return responder({ erro: 'Esse e-mail já tem conta, mas não foi possível ligar.' }, 409);
    }

    // 3. Amarra a conta nova ao profissional.
    await admin.from('barbeiros')
      .update({ perfil_id: criado.user.id, email: limpo })
      .eq('id', barbeiro_id);

    await admin.from('perfis')
      .update({ papel: 'barbeiro' })
      .eq('id', criado.user.id);

    return responder({ ok: true, email: limpo, senha });

  } catch (e) {
    console.error(e);
    return responder({ erro: String(e) }, 500);
  }
});
