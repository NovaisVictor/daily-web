# Daily Web para macOS

Cliente nativo (SwiftUI) do daily-web. Ele usa o mesmo servidor e a mesma API do
painel web, sem nenhuma mudança no servidor.

O plano, as decisões e as evidências de teste estão em [docs/](docs/plan.md).

## Requisitos

- macOS 26 (Tahoe) ou superior, em Mac com Apple Silicon.
- Um servidor daily-web acessível e uma conta nele.
  - O endereço precisa ser HTTPS.
  - Se o servidor estiver na rede local (`localhost`, `*.local` ou um IP), o app
    aceita HTTP.

## Instalação

```sh
brew tap novaisvictor/tap
brew install --cask daily-web
```

O Homebrew 6 ou superior pede para confiar no tap na primeira vez. Siga a
instrução que ele mostrar ([Tap Trust](https://docs.brew.sh/Tap-Trust)).

### Primeira abertura

O app é assinado com um certificado próprio do projeto, sem o Apple Developer ID
pago e sem notarização. Para o macOS não bloquear a primeira abertura de cada
versão, o cask remove o atributo de quarentena na instalação, como faz o cask do
HyprMac no mesmo tap.

Se mesmo assim o macOS recusar abrir, rode:

```sh
xattr -dr com.apple.quarantine /Applications/DailyWeb.app
```

Como a assinatura do projeto se mantém entre versões, o macOS não pede de novo o
acesso à sessão guardada no Keychain a cada atualização.

O macOS só entrega a sessão do Keychain sem pedir senha ao app com a mesma
assinatura de quem a gravou. Por isso o `make app` reassina o build Debug com a
identidade "Daily Web Self-Signed" quando ela existe neste Mac: o build local e a
versão do brew passam a ser o mesmo app para o Keychain.

### Atualizar e remover

```sh
brew upgrade --cask daily-web
brew uninstall --cask daily-web          # mantém sessão e preferências
brew uninstall --zap --cask daily-web    # apaga também os dados locais
```

## Primeiro uso

1. Informe o endereço do servidor (por exemplo `https://daily.suaempresa.com`), o
   usuário e a senha. São os mesmos do painel web.
2. A sessão dura 30 dias, como no web, e fica no Keychain.
3. Os avisos do sistema se ligam no sino → "Avisar no computador".
4. Em Configurações (⌘,) → Geral ficam o atalho global para abrir o app (padrão
   ⌃⌥⌘D) e a opção de abrir ao iniciar o Mac.

O app fica na barra de menus mesmo sem janela aberta. Para encerrar de vez, use
**Sair** (⌘Q).

### O que difere do web

- O início usa uma barra lateral, não o grid arrastável.
- A aparência escolhida no web não chega ao app, porque o servidor não tem uma
  rota de leitura para ela. Cada um guarda a sua.
- O corpo dos e-mails aparece como texto, porque o servidor só envia texto.
- Conectar Google ou Slack abre o navegador, onde o fluxo de autorização acontece.

A lista completa está em [docs/validation.md](docs/validation.md).

## Desenvolvimento

Requer o Xcode 26.6 ou superior.

```sh
cd macos
make build   # compila o pacote DailyKit
make test    # roda os testes
make lint    # confere a formatação (swift format)
make app     # compila o app pelo Xcode
make check   # lint + testes + app
make clean   # apaga os builds (use se os testes caírem com sinal 10 ou 11)
```

Para abrir no Xcode, use `macos/DailyWeb.xcodeproj`.

Para usar contra um servidor local, rode `npm run dev` na raiz do repositório e
informe `http://localhost:8010` na tela de login.

As regras para quem altera o código, incluindo agentes, estão em [AGENTS.md](AGENTS.md).

## Publicar uma versão

A versão é compilada e publicada a partir deste Mac. Não há build no GitHub
Actions, porque a identidade de assinatura fica no Keychain de login de quem
publica.

Antes de rodar:

- o commit precisa estar enviado ao fork, sem mudanças locais;
- o `gh` precisa estar logado com permissão de escrita em `NovaisVictor/daily-web`
  e `NovaisVictor/homebrew-tap`.

```sh
cd macos
make release VERSION=0.2.0
```

O `make release` roda o `make check` e depois o `Scripts/release.sh`, que faz em
ordem:

1. Confere a versão, o estado do git e as permissões do `gh`.
2. Compila em Release, só arm64, protegido pelo `Scripts/guarded.sh`.
3. Assina com `Scripts/sign.sh`. Na primeira vez, cria a identidade
   "Daily Web Self-Signed" no Keychain de login.
4. Valida a assinatura, a arquitetura, a versão e o bundle id do app.
5. Gera o zip e publica a release `macos-v0.2.0` no fork, com as notas geradas
   pelo GitHub.
6. Gera o `Casks/daily-web.rb` a partir de `Scripts/daily-web.rb.tmpl` e envia ao
   tap.

Se a release já existir no fork (uma execução anterior parou antes do tap), o
script reaproveita o zip publicado e só atualiza o cask.

Para quem já tem o app instalado:

```sh
brew update && brew upgrade --cask daily-web
```

## Estrutura

| Caminho | O que é |
|---|---|
| `App/` | Target do app: cenas, barra de menus, composição |
| `Packages/DailyKit/` | Todo o código: modelos, API, armazenamento, design, núcleo e uma pasta por funcionalidade |
| `Config/` | `xcconfig`, `Info.plist` e entitlements |
| `Scripts/` | Assinatura, release e o modelo do cask |
| `docs/` | Spec, plano, pesquisa, contrato da API, tarefas, auditoria e validação |
