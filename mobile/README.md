# Apps Flutter

Dois apps, como no Gerenciamento Max (públicos, ícones e fichas de loja diferentes), com o código comum num pacote:

| Pasta | App | Para quem | ID (Android / iOS) |
|---|---|---|---|
| `cliente/` | **Loja Max** | Clientes: escolher a loja, vitrine, carrinho, pedidos, avisos e promoções | `io.github.agsterr.lojamax` |
| `lojista/` | **Loja Max Lojista** | Quem vende: abrir a loja, pedidos, produtos com fotos, estoque, promoções, resumo, equipe, auditoria. O admin da plataforma também entra por aqui | `io.github.agsterr.lojamax.lojista` |
| `core/` | pacote `loja_core` | API, sessão, modelos, tema, avisos (push/sino/segundo plano) e telas comuns (entrar, conta, segurança, sino, pedido) | — |
| `telas/` | gerador de imagens | Captura as telas dos dois apps com dados de exemplo | — |

Conta no app errado (cliente no app do lojista, ou equipe no app do cliente) vê uma tela explicando qual app usar.
Estado só com `ChangeNotifier` (sessão, carrinho, loja aberta) e `StatefulWidget`, sem frameworks extras.

## Rodando

```bash
cd mobile/cliente   # ou mobile/lojista
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8080        # emulador Android
```

Testes e análise:
```bash
for d in core cliente lojista telas; do (cd $d && flutter analyze && ([ -d test ] && flutter test || true)); done
```

| `--dart-define` | Uso |
|---|---|
| `API_URL` | URL da API (em produção **HTTPS**; o release do Android recusa HTTP) |
| `SUPPORT_EMAIL` | contato mostrado na tela de conta bloqueada |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | push (veja `../docs/PUSH.md`); o `FIREBASE_APP_ID` é diferente em cada app |
| `STORE_SLUG` | só no app do cliente: versão de **uma loja só** (com a marca do lojista), abre direto nela |

## Avisos
- `core/lib/src/push.dart`: Firebase Messaging (mostra o push com o app aberto, confirma o recebimento, abre o pedido/produto ao tocar).
- `core/lib/src/background.dart`: Workmanager confere o sino a cada 15 min (1 h com push) e mostra o que for novo.
- `core/lib/src/notifications.dart`: canais `pedidos` e `promocoes` e notificações locais.

## Imagens das telas
`cd telas && flutter test telas_test.dart` gera `../../docs/telas/cliente/*.png` e `../../docs/telas/lojista/*.png`
(API simulada; as fotos dos produtos são as ilustrações de `telas/fotos`).

## Release Android
Em cada app, crie `android/key.properties` (não versionado) com `storePassword`, `keyPassword`, `keyAlias` e
`storeFile`; sem ele o release é assinado com a chave de debug (só para teste).
`flutter build appbundle --release --dart-define=API_URL=https://... --dart-define=FIREBASE_...`
