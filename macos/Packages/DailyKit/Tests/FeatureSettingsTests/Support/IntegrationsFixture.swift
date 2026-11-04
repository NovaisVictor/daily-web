import Foundation

/// `GET /api/integrations`: the catalog as the dev server sends it (from
/// `lib/modules.ts`), with made-up connections.
nonisolated let integrationsFixture = Data(
  #"""
  {
   "vaultReady": true,
   "mstodoAvailable": false,
   "googleConfigured": false,
   "googleRedirectUri": "https://daily.example.com/api/integrations/agenda/google/callback",
   "slackConfigured": false,
   "slackRedirectUri": "https://daily.example.com/api/integrations/slack/callback",
   "catalog": {
    "email": {
     "id": "email",
     "label": "E-mail",
     "summary": "Caixa de entrada, responder, etiquetar e arquivar.",
     "multi": true,
     "instructions": [
      "Conecta por IMAP com senha de app — nenhum OAuth, nenhum cadastro de aplicativo.",
      "Gmail: ative a verificação em duas etapas e gere uma senha em myaccount.google.com/apppasswords.",
      "Outlook/Microsoft 365: gere em account.microsoft.com/security, em Opções de segurança avançadas.",
      "iCloud: gere em account.apple.com, na seção Segurança.",
      "Qualquer outro provedor IMAP funciona escolhendo \"Outro\" e preenchendo host e porta."
     ],
     "fields": [
      {
       "name": "preset",
       "label": "Provedor",
       "type": "select",
       "required": true,
       "defaultValue": "gmail",
       "options": [
        {
         "value": "gmail",
         "label": "Gmail"
        },
        {
         "value": "outlook",
         "label": "Outlook / Microsoft 365"
        },
        {
         "value": "icloud",
         "label": "iCloud"
        },
        {
         "value": "yahoo",
         "label": "Yahoo"
        },
        {
         "value": "fastmail",
         "label": "Fastmail"
        },
        {
         "value": "custom",
         "label": "Outro (IMAP manual)"
        }
       ]
      },
      {
       "name": "user",
       "label": "Endereço de e-mail",
       "type": "text",
       "required": true,
       "placeholder": "voce@gmail.com"
      },
      {
       "name": "password",
       "label": "Senha de app",
       "type": "password",
       "secret": true,
       "required": true,
       "help": "A senha de app, não a senha da sua conta."
      },
      {
       "name": "imapHost",
       "label": "Servidor IMAP",
       "type": "text",
       "required": true,
       "showWhen": {
        "field": "preset",
        "equals": [
         "custom"
        ]
       }
      },
      {
       "name": "imapPort",
       "label": "Porta IMAP",
       "type": "number",
       "defaultValue": "993",
       "showWhen": {
        "field": "preset",
        "equals": [
         "custom"
        ]
       }
      },
      {
       "name": "smtpHost",
       "label": "Servidor SMTP",
       "type": "text",
       "help": "Usado só para responder e-mails.",
       "showWhen": {
        "field": "preset",
        "equals": [
         "custom"
        ]
       }
      },
      {
       "name": "smtpPort",
       "label": "Porta SMTP",
       "type": "number",
       "defaultValue": "465",
       "showWhen": {
        "field": "preset",
        "equals": [
         "custom"
        ]
       }
      }
     ]
    },
    "agenda": {
     "id": "agenda",
     "label": "Agenda",
     "summary": "Compromissos no período que você escolher.",
     "multi": true,
     "instructions": [
      "Para contas Google, conecte pelo botão do Google: funciona com conta pessoal e corporativa, e não quebra quando o link muda.",
      "O link iCal serve para os demais provedores — Outlook, Apple, Fastmail, Nextcloud.",
      "Google Agenda: Configurações → clique na agenda à esquerda → \"Integrar agenda\" → \"Endereço secreto no formato iCal\" (termina em .ics).",
      "Outlook: Configurações → Agenda → Agendas compartilhadas → Publicar, e copie o link ICS.",
      "Em conta corporativa o administrador costuma bloquear o link iCal; nesse caso só a conexão pelo Google funciona.",
      "O painel lê os compromissos e cria blocos de foco após sua confirmação.",
      "Quantos dias aparecem é escolha sua, nos botões do próprio painel."
     ],
     "fields": [
      {
       "name": "provider",
       "label": "Origem",
       "type": "text",
       "hidden": true,
       "defaultValue": "ics"
      },
      {
       "name": "account",
       "label": "Conta Google",
       "type": "text",
       "hidden": true
      },
      {
       "name": "refreshToken",
       "label": "Token do Google",
       "type": "password",
       "secret": true,
       "hidden": true
      },
      {
       "name": "scope",
       "label": "Permissões do Google",
       "type": "text",
       "hidden": true
      },
      {
       "name": "calendarIds",
       "label": "Agendas escolhidas",
       "type": "text",
       "hidden": true
      },
      {
       "name": "icsUrl",
       "label": "URL do iCal (.ics)",
       "type": "url",
       "secret": true,
       "required": true,
       "placeholder": "https://calendar.google.com/calendar/ical/.../basic.ics",
       "help": "Copie o \"Endereço secreto no formato iCal\" — não o endereço da barra do navegador.",
       "showWhen": {
        "field": "provider",
        "equals": [
         "ics"
        ]
       }
      }
     ]
    },
    "jira": {
     "id": "jira",
     "label": "Jira",
     "summary": "Suas issues, em hierarquia, o que entregou hoje e menções.",
     "multi": false,
     "instructions": [
      "Precisa de um API token do Atlassian, que é gratuito.",
      "Gere em id.atlassian.com/manage-profile/security/api-tokens.",
      "O domínio é o começo da URL: em acme.atlassian.net, o domínio é \"acme\"."
     ],
     "fields": [
      {
       "name": "cloud",
       "label": "Domínio Jira Cloud",
       "type": "text",
       "required": true,
       "placeholder": "acme",
       "help": "Só o nome, ou a URL inteira — os dois funcionam."
      },
      {
       "name": "email",
       "label": "E-mail da conta Atlassian",
       "type": "text",
       "required": true
      },
      {
       "name": "token",
       "label": "API token",
       "type": "password",
       "secret": true,
       "required": true
      }
     ]
    },
    "pulls": {
     "id": "pulls",
     "label": "Pull requests",
     "summary": "PRs abertos esperando por você.",
     "multi": false,
     "instructions": [
      "Precisa de um personal access token do GitHub, que é gratuito.",
      "Gere em github.com/settings/tokens.",
      "Escopo \"repo\" para repositórios privados; para só públicos, nenhum escopo basta.",
      "Os repositórios acompanhados são configurados no próprio painel."
     ],
     "fields": [
      {
       "name": "token",
       "label": "Personal access token",
       "type": "password",
       "secret": true,
       "required": true
      },
      {
       "name": "repos",
       "label": "Repositórios",
       "type": "text",
       "placeholder": "dono/repo, dono/outro",
       "help": "Separados por vírgula. Dá para editar depois direto no painel."
      },
      {
       "name": "repoAuthors",
       "label": "Autores acompanhados",
       "type": "text",
       "hidden": true
      }
     ]
    },
    "slack": {
     "id": "slack",
     "label": "Slack",
     "summary": "menções e mensagens diretas",
     "multi": false,
     "instructions": [
      "Clique em \"Conectar com Slack\" e autorize o acesso à sua conta.",
      "Se o workspace exigir aprovação de aplicativos, uma pessoa administradora talvez precise aprovar o app.",
      "A conexão é somente da sua conta e mostra menções e mensagens diretas não lidas."
     ],
     "fields": [
      {
       "name": "token",
       "label": "Token do Slack",
       "type": "password",
       "secret": true,
       "hidden": true
      },
      {
       "name": "userId",
       "label": "Usuário do Slack",
       "type": "text",
       "hidden": true
      },
      {
       "name": "teamId",
       "label": "Workspace",
       "type": "text",
       "hidden": true
      },
      {
       "name": "teamName",
       "label": "Nome do workspace",
       "type": "text",
       "hidden": true
      },
      {
       "name": "scope",
       "label": "Permissões",
       "type": "text",
       "hidden": true
      }
     ]
    },
    "tasks": {
     "id": "tasks",
     "label": "Tarefas",
     "summary": "Lista de tarefas com subtarefas, prazo e prioridade.",
     "multi": false,
     "alwaysAvailable": true,
     "instructions": [
      "O padrão guarda as tarefas no próprio banco da app: funciona na hora, sem credencial.",
      "Microsoft To Do só aparece se a CLI mstodo estiver instalada na máquina."
     ],
     "fields": [
      {
       "name": "provider",
       "label": "Onde guardar",
       "type": "select",
       "required": true,
       "defaultValue": "local",
       "options": [
        {
         "value": "local",
         "label": "Neste servidor (padrão)"
        },
        {
         "value": "mstodo",
         "label": "Microsoft To Do (CLI mstodo)"
        }
       ]
      },
      {
       "name": "clientId",
       "label": "Application (client) ID",
       "type": "text",
       "showWhen": {
        "field": "provider",
        "equals": [
         "mstodo"
        ]
       }
      },
      {
       "name": "list",
       "label": "Nome da lista",
       "type": "text",
       "showWhen": {
        "field": "provider",
        "equals": [
         "mstodo"
        ]
       }
      }
     ]
    },
    "notes": {
     "id": "notes",
     "label": "Notas rápidas",
     "summary": "Bloco de notas com abas em Markdown, com cópia opcional no Google Drive.",
     "multi": false,
     "alwaysAvailable": true,
     "instructions": [
      "Funciona sem credencial nenhuma: as notas ficam no banco da própria app.",
      "Conecte o Google Drive para ter uma cópia fora deste servidor. Cada nota vira um arquivo .md na pasta \"daily-web — notas\".",
      "A app só enxerga os arquivos que ela mesma criou no seu Drive — nada mais.",
      "Numa instalação nova, conectar a mesma conta traz as notas de volta.",
      "A cópia vai daqui para o Drive: editar o arquivo direto no Drive não altera a nota, e a próxima edição aqui o sobrescreve.",
      "As notas que já existiam antes de conectar sobem quando forem editadas."
     ],
     "fields": [
      {
       "name": "provider",
       "label": "Origem",
       "type": "text",
       "hidden": true
      },
      {
       "name": "account",
       "label": "Conta Google",
       "type": "text",
       "hidden": true
      },
      {
       "name": "refreshToken",
       "label": "Token do Google",
       "type": "password",
       "secret": true,
       "hidden": true
      }
     ]
    }
   },
   "modules": [
    {
     "module": "email",
     "label": "E-mail",
     "summary": "Caixa de entrada, responder, etiquetar e arquivar.",
     "multi": true,
     "enabled": true,
     "configured": true,
     "connections": [
      {
       "id": "conn-mail-1",
       "module": "email",
       "label": "Trabalho",
       "visible": {
        "preset": "gmail",
        "user": "voce@example.com"
       },
       "secretsSet": [
        "password"
       ],
       "updatedAt": "2026-10-01T10:00:00.000Z",
       "unreadable": false
      },
      {
       "id": "conn-mail-2",
       "module": "email",
       "label": "Antiga",
       "visible": {},
       "secretsSet": [],
       "updatedAt": "2026-10-01T10:00:00.000Z",
       "unreadable": true
      }
     ]
    },
    {
     "module": "agenda",
     "label": "Agenda",
     "summary": "Compromissos no período que você escolher.",
     "multi": true,
     "enabled": false,
     "configured": false,
     "connections": [
      {
       "id": "conn-cal-1",
       "module": "agenda",
       "label": "Google Agenda",
       "visible": {
        "provider": "google",
        "account": "voce@example.com"
       },
       "secretsSet": [
        "refreshToken"
       ],
       "updatedAt": "2026-10-01T10:00:00.000Z",
       "unreadable": false
      }
     ]
    },
    {
     "module": "tasks",
     "label": "Tarefas",
     "summary": "Lista de tarefas com subtarefas, prazo e prioridade.",
     "multi": false,
     "enabled": true,
     "configured": false,
     "connections": []
    },
    {
     "module": "notes",
     "label": "Notas rápidas",
     "summary": "Bloco de notas com abas em Markdown.",
     "multi": false,
     "enabled": true,
     "configured": true,
     "connections": [
      {
       "id": "conn-notes-1",
       "module": "notes",
       "label": "Google Drive",
       "visible": {
        "provider": "google",
        "account": "voce@example.com"
       },
       "secretsSet": [
        "refreshToken"
       ],
       "updatedAt": "2026-10-02T10:00:00.000Z",
       "unreadable": false
      }
     ]
    },
    {
     "module": "jira",
     "label": "Jira",
     "summary": "Suas issues, em hierarquia, o que entregou hoje e menções.",
     "multi": false,
     "enabled": true,
     "configured": true,
     "connections": [
      {
       "id": "conn-jira-1",
       "module": "jira",
       "label": "Jira",
       "visible": {
        "cloud": "acme",
        "email": "voce@example.com"
       },
       "secretsSet": [
        "token"
       ],
       "updatedAt": "2026-10-01T10:00:00.000Z",
       "unreadable": false
      }
     ]
    }
   ]
  }
  """#.utf8)
