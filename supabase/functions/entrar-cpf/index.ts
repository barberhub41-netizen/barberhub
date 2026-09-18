// ============================================================
// BarberHub — Edge Function "entrar-cpf"
// Login com CPF e senha.
//
// O Supabase só autentica por e-mail. Esta função descobre o
// e-mail a partir do CPF usando a chave administrativa, faz a
// entrada e devolve a sessão. O e-mail nunca sai daqui: se o
// site pudesse consultar CPF → e-mail, qualquer um descobriria
// de quem é cada CPF.
//
// Como publicar, pelo navegador:
//   Painel → Edge Functions → Deploy a new function
//   Nome: entrar-cpf
//   Cole este arquivo inteiro e publique.
// ============================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_PROJETO = Deno.env.get('SUPABASE_URL')!;
const CHAVE_ADMIN = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CHAVE_PUBLICA = Deno.env.get('SUPABASE_ANON_KEY')!;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

// Uma pausa em toda tentativa, certa ou errada, para não valer a
// pena varrer CPFs com senha chutada.
const espera = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') {
    return new Response('Método não permitido', { status: 405, headers: CORS });
  }

  const responder = (corpo: unknown, status = 200) =>
    new Response(JSON.stringify(corpo), {
      status, headers: { ...CORS, 'Content-Type': 'application/json' }
    });

  // a mesma resposta para CPF inexistente e senha errada
  const recusar = async () => {
    await espera(600);
    return responder({ erro: 'CPF ou senha incorretos.' }, 401);
  };

  try {
    const { cpf, senha } = await req.json();
    const digitos = String(cpf ?? '').replace(/\D/g, '');

    if (digitos.length !== 11 || !senha) {
      return responder({ erro: 'Informe o CPF e a senha.' }, 400);
    }

    const admin = createClient(URL_PROJETO, CHAVE_ADMIN);

    const { data: perfilId, error: erroBusca } = await admin
      .rpc('conta_por_cpf', { p_cpf: digitos });

    if (erroBusca || !perfilId) return await recusar();

    const { data: usuario, error: erroUsuario } =
      await admin.auth.admin.getUserById(perfilId as string);

    if (erroUsuario || !usuario?.user?.email) return await recusar();

    // a entrada em si acontece com a chave pública, como no site
    const comum = createClient(URL_PROJETO, CHAVE_PUBLICA);
    const { data: sessao, error: erroEntrada } = await comum.auth.signInWithPassword({
      email: usuario.user.email,
      password: String(senha)
    });

    if (erroEntrada || !sessao?.session) return await recusar();

    return responder({
      ok: true,
      access_token: sessao.session.access_token,
      refresh_token: sessao.session.refresh_token
    });

  } catch (e) {
    console.error(e);
    return responder({ erro: 'Não foi possível entrar agora.' }, 500);
  }
});
