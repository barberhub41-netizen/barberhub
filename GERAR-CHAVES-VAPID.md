# Gerar as chaves VAPID (pelo navegador, sem instalar nada)

O push precisa de um par de chaves. A pública vai no site; a privada
fica só nos segredos da Edge Function.

1. Abra o seu site publicado
2. Aperte **F12** → aba **Console**
3. Cole o bloco abaixo e aperte Enter

```js
(async () => {
  const par = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']
  );
  const b64 = (b) => btoa(String.fromCharCode(...new Uint8Array(b)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const publica = b64(await crypto.subtle.exportKey('raw', par.publicKey));
  const jwk = await crypto.subtle.exportKey('jwk', par.privateKey);

  console.log('%cVAPID_PUBLICA', 'color:#d86b3f;font-weight:bold', publica);
  console.log('%cVAPID_PRIVADA', 'color:#d86b3f;font-weight:bold', jwk.d);
})();
```

4. Vão aparecer duas linhas. Guarde as duas.

## Onde cada uma vai

| Chave | Onde |
|---|---|
| `VAPID_PUBLICA` | no `config.js` do site, na constante `VAPID_PUBLICA` |
| `VAPID_PRIVADA` | painel do Supabase → Edge Functions → Secrets |

A pública pode ficar no repositório: ela é feita para aparecer no
navegador. **A privada nunca.** Quem tiver ela consegue mandar
notificação em nome do seu site.

## Segredos da Edge Function

Painel → Edge Functions → **Secrets** → Add new secret:

```
VAPID_PUBLICA   a chave pública
VAPID_PRIVADA   a chave privada
VAPID_CONTATO   mailto:seu@email.com
```

## Segredos do banco (para o gatilho conseguir chamar a função)

SQL Editor, trocando os valores:

```sql
select vault.create_secret('https://njjbghdhjeotatwsoxke.supabase.co', 'url_projeto');
select vault.create_secret('SUA_SERVICE_ROLE_KEY', 'chave_servico');
```

A service_role fica **dentro do banco**, no Vault, que é o lugar
certo dela. Continua valendo: nunca em arquivo do site.

Para conferir depois:

```sql
select name from vault.secrets order by name;
```
