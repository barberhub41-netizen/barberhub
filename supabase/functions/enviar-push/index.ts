// ============================================================
// BarberHub — Edge Function "enviar-push"
// Recebe um aviso e entrega como notificação push nos aparelhos
// que aquela pessoa inscreveu.
//
// Como publicar, pelo navegador:
//   Painel do Supabase → Edge Functions → Deploy a new function
//   Nome: enviar-push
//   Cole este arquivo inteiro e publique.
//
// Antes, cadastre os segredos em Edge Functions → Secrets:
//   VAPID_PUBLICA    chave pública (a mesma que vai no site)
//   VAPID_PRIVADA    chave privada — só aqui, nunca no repositório
//   VAPID_CONTATO    mailto:seu@email.com
// ============================================================

import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const PUBLICA = Deno.env.get('VAPID_PUBLICA')!;
const PRIVADA = Deno.env.get('VAPID_PRIVADA')!;
const CONTATO = Deno.env.get('VAPID_CONTATO') ?? 'mailto:contato@barberhub.app';

webpush.setVapidDetails(CONTATO, PUBLICA, PRIVADA);

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Método não permitido', { status: 405 });
  }

  try {
    const { perfil_id, titulo, mensagem, link, tipo } = await req.json();

    if (!perfil_id || !titulo) {
      return new Response(JSON.stringify({ erro: 'Faltou perfil_id ou titulo' }), {
        status: 400, headers: { 'Content-Type': 'application/json' }
      });
    }

    // todos os aparelhos daquela pessoa
    const { data: inscricoes, error } = await supabase
      .from('push_assinaturas')
      .select('id, endpoint, p256dh, auth')
      .eq('perfil_id', perfil_id);

    if (error) throw error;
    if (!inscricoes?.length) {
      return new Response(JSON.stringify({ enviados: 0, motivo: 'sem aparelho inscrito' }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const carga = JSON.stringify({ titulo, mensagem, link, tipo });

    let enviados = 0;
    const mortas: string[] = [];

    await Promise.all(inscricoes.map(async (i) => {
      try {
        await webpush.sendNotification(
          { endpoint: i.endpoint, keys: { p256dh: i.p256dh, auth: i.auth } },
          carga
        );
        enviados++;
      } catch (e) {
        // 404 ou 410 = o navegador descartou a inscrição
        const codigo = (e as { statusCode?: number }).statusCode;
        if (codigo === 404 || codigo === 410) mortas.push(i.id);
        else console.error('Falha ao enviar para', i.endpoint, e);
      }
    }));

    if (mortas.length) {
      await supabase.from('push_assinaturas').delete().in('id', mortas);
    }

    if (enviados) {
      await supabase.from('push_assinaturas')
        .update({ usado_em: new Date().toISOString() })
        .eq('perfil_id', perfil_id);
    }

    return new Response(JSON.stringify({ enviados, removidas: mortas.length }), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ erro: String(e) }), {
      status: 500, headers: { 'Content-Type': 'application/json' }
    });
  }
});
