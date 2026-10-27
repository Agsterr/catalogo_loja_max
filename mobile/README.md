# App Loja Max (Flutter)

Um app só para os dois públicos: quem entra como **cliente** (ou sem conta) vê a vitrine, o carrinho e os pedidos;
quem entra com uma conta da **equipe** (dono/funcionário) cai na gestão da loja. Estado só com `ChangeNotifier`
(sessão e carrinho) e `StatefulWidget`, sem frameworks extras.

```bash
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8080        # emulador Android
flutter analyze && flutter test
```

| `--dart-define` | Uso |
|---|---|
| `API_URL` | URL da API (em produção **HTTPS**; o release do Android recusa HTTP) |
| `SUPPORT_EMAIL` | contato mostrado na tela de conta bloqueada |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | push (veja `../docs/PUSH.md`) |

## Avisos
- `lib/push.dart`: Firebase Messaging (mostra o push com o app aberto, confirma o recebimento, abre o pedido/produto ao tocar).
- `lib/background.dart`: Workmanager confere o sino a cada 15 min (1 h com push) e mostra o que for novo.
- `lib/notifications.dart`: canais `pedidos` e `promocoes` e notificações locais.

## Pastas
```
lib/
├── main.dart, app_scope.dart, session.dart, cart.dart, api_client.dart, models.dart
├── screens/   vitrine, produto, carrinho/fechar pedido, pedidos, avisos, conta, login
└── store/     gestão: pedidos, produtos (fotos e estoque), promoções, resumo, clientes, equipe, dados da loja
```

## Release Android
Pacote `io.github.agsterr.lojamax`. Crie `android/key.properties` (não versionado) com `storePassword`, `keyPassword`,
`keyAlias` e `storeFile`; sem ele o release é assinado com a chave de debug (só para teste).
`flutter build appbundle --release --dart-define=API_URL=https://... --dart-define=FIREBASE_...`
