# Google Play — publicação dos apps Loja Max

O workflow **Play Store** (`.github/workflows/play-release.yml`) roda a cada push na `main` que mexe em
`mobile/`: builda o `.aab` dos três apps e envia para a faixa de **teste fechado (alpha)**. Para mudar a faixa sem
editar o arquivo, crie a variável `PLAY_TRACK` (`internal`, `alpha`, `beta` ou `production`). Sem a conta de serviço
configurada, o `.aab` fica nos *Artifacts* da execução (útil para o primeiro envio manual).

| App | Pacote | Pasta | Ficha (`mobile/store/`) |
|---|---|---|---|
| Loja Max (cliente) | `io.github.agsterr.lojamax` | `mobile/cliente` | `cliente/android/pt-BR` |
| Loja Max Lojista | `io.github.agsterr.lojamax.lojista` | `mobile/lojista` | `lojista/android/pt-BR` |
| Loja Max Entregador | `io.github.agsterr.lojamax.entregador` | `mobile/entregador` | `entregador/android/pt-BR` |

## 1. Uma vez só, no Play Console

1. **Criar os três apps** (*Criar app*, idioma português, app gratuito). Os pacotes são definidos pelo `applicationId`
   e não mudam depois. A API da Play não cria apps.
2. **Chave de upload.** Gere uma vez, **fora do repositório** (um arquivo serve para os três apps):
   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   Guarde o arquivo e as senhas em um gerenciador de senhas. Se perder, a Play precisa resetar a chave.
3. **Primeiro `.aab` manual.** Rode o workflow (*Actions → Play Store → Run workflow*) depois dos secrets da
   assinatura (passo 4), baixe o `.aab` em *Artifacts* e envie em *Testar e lançar → Teste fechado* de cada app.
   Aceite o **Assinatura de apps do Google Play**: a chave de upload passa a ser a do keystore.
4. **Conta de serviço** (Google Cloud Console, mesma conta da Play):
   - crie um projeto (ou use um existente) e ative a *Google Play Android Developer API*;
   - *IAM → Contas de serviço → Criar*; em *Chaves*, gere uma chave **JSON**;
   - no Play Console, *Usuários e permissões → Convidar usuário* com o e-mail da conta de serviço, acesso aos três
     apps e permissão de **lançar em faixas de teste** (e produção, se quiser).
5. **Pendente antes de a Play aceitar a 1ª versão**: enquanto o app não foi aprovado, o envio fica como rascunho
   (padrão). Depois da primeira aprovação, crie a variável `PLAY_RELEASE_STATUS=completed`.

Conta **pessoal** criada depois de nov/2023: a Play exige **teste fechado com 12 testadores por 14 dias** antes de
liberar a produção. Conta de **organização** não tem essa exigência.

## 2. Secrets e variáveis no GitHub

*Settings → Secrets and variables → Actions*. Os valores **nunca** vão para o repositório nem para o chat.

| Tipo | Nome | Conteúdo |
|---|---|---|
| Secret | `ANDROID_KEYSTORE_BASE64` | keystore em base64 (veja abaixo) |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | senha do keystore |
| Secret | `ANDROID_KEY_ALIAS` | `upload` (o alias usado no `keytool`) |
| Secret | `ANDROID_KEY_PASSWORD` | senha da chave |
| Secret | `PLAY_SERVICE_ACCOUNT_JSON` | JSON da conta de serviço (passo 1.4) |
| Secret | `FIREBASE_API_KEY`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | veja [PUSH.md](PUSH.md) |
| Secret | `FIREBASE_APP_ID_CLIENTE`, `FIREBASE_APP_ID_LOJISTA`, `FIREBASE_APP_ID_ENTREGADOR` | um por app (veja [PUSH.md](PUSH.md)) |
| Variable | `API_URL` | `https://lojamax.focodev.com.br` (ou seu domínio, em HTTPS) |
| Variable | `PUBLIC_URL` | o mesmo endereço; é de onde saem as páginas `/privacidade`, `/termos` e `/excluir-conta` |
| Variable | `PLAY_TRACK` | opcional: `alpha` (padrão), `internal`, `beta` ou `production` |

Keystore em base64 e envio para o GitHub, a partir da pasta onde está o `upload-keystore.jks`:
```bash
base64 -w0 upload-keystore.jks > keystore.b64
gh secret set ANDROID_KEYSTORE_BASE64 -R Agsterr/catalogo_loja_max < keystore.b64
rm keystore.b64
```
Depois: `gh secret set PLAY_SERVICE_ACCOUNT_JSON -R Agsterr/catalogo_loja_max < chave.json` e apague `chave.json`.

## 3. Ficha da loja (manual, uma vez por app)

Textos prontos em `mobile/store/<app>/android/pt-BR/` (`title.txt` ≤ 30 caracteres, `short_description.txt` ≤ 80,
`full_description.txt`). Ícone de 512 × 512 em `mobile/store/<app>/android/icon-512.png`.

Ainda falta, antes do envio para produção:
- **Prints de celular** no formato 1080 × 1920 (ou 9:16). Os de `docs/telas/` têm 780 × 1688, proporção acima de 2:1,
  que a Play não aceita. Gere de novo com `cd mobile/telas && flutter test telas_test.dart` e reduza/enquadre para 9:16.
- **Imagem de destaque** 1024 × 500.

Links para o formulário:
- Política de privacidade: `https://lojamax.focodev.com.br/privacidade`
- Termos: `https://lojamax.focodev.com.br/termos`
- Exclusão de conta (URL obrigatória para apps com conta): `https://lojamax.focodev.com.br/excluir-conta`
- E-mail de contato: confirme `LEGAL_EMAIL` no `.env` do servidor (padrão do modelo: `contato@lojamax.com.br`) e use o seu.

## 4. Formulários do Play Console

- **Permissões sensíveis** (*Conteúdo do app → Permissões*): os três apps pedem `INTERNET`, notificações
  (`POST_NOTIFICATIONS`) e localização (`ACCESS_COARSE/FINE_LOCATION`). Justificativa:
  - **cliente**: só `COARSE`, com precisão baixa, para ver lojas perto de você (quando toca no botão) e calcular a
    entrega no carrinho;
  - **lojista**: `FINE` e `COARSE` declarados, usados só quando o lojista toca em "usar minha localização" para marcar
    o ponto da loja. Como a leitura é de precisão baixa, o app só usa a aproximada. Avalie remover `FINE` do
    manifesto de `lojista/android/app/src/main/AndroidManifest.xml` antes do envio;
  - **entregador**: `FINE` e `COARSE`, para o cadastro, a conta e o mural de corridas perto de você, e para enviar a
    posição durante uma corrida ativa, só com o app aberto. Não há localização em segundo plano; se isso mudar, o
    formulário de localização em segundo plano passa a ser obrigatório.
  Confira no *App bundle explorer → Permissões* do Play Console se só aparecem essas permissões.
- **Segurança dos dados**: coleta **sim**; compartilha **não**; criptografado em trânsito **sim**; pedido de exclusão
  **sim** (link acima). Tipos a declarar:
  - cliente: nome, e-mail/telefone de conta (se houver) e localização aproximada (lojas perto de você e entrega);
  - lojista: nome, e-mail e número de telefone (conta e funcionalidade); dados da loja e dos pedidos;
  - entregador: nome, e-mail, telefone e **localização** (corridas e acompanhamento da entrega, só durante o uso).
- **Classificação do conteúdo**: questionário com resposta "sem conteúdo sensível".
- **Público-alvo**: 18 anos ou mais (não é app para crianças).
- **Acesso ao app**: informe uma conta de demonstração para o revisor de cada app (crie no servidor de produção e
  guarde a senha só no Play Console).
- **Conta de demonstração** e **notas para a revisão**: o cliente não exige login para ver a vitrine; o lojista e o
  entregador precisam de conta. Explique isso no campo de notas.

## 5. Versão e numeração

- `versionName` vem do `version:` do `pubspec.yaml` (hoje `1.0.0`).
- `versionCode` = `1000 + número da execução`: a Play só aceita número maior que o último enviado, e a execução sempre
  cresce.
- Para mudar a versão exibida, altere a parte antes do `+` no `pubspec.yaml`.

## 6. Verificação

- Local (exige Flutter e Dart com a versão do projeto; o CI já faz isso): `cd mobile/cliente && flutter analyze && flutter test`.
- No CI, o job *Apps Flutter* roda analyze e teste dos cinco pacotes e gera os APKs de release.
- Depois de cada envio, veja o resumo da execução (*Step Summary*) e o status em *Testar e lançar* no Play Console.
