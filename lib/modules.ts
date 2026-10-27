// Catálogo de módulos. É a única fonte da verdade sobre o que existe, o que
// cada integração pede e onde a pessoa consegue cada credencial — a tela de
// configuração é gerada a partir daqui, então acrescentar um módulo não exige
// mexer em formulário nenhum.

export type ModuleId = 'email' | 'agenda' | 'jira' | 'pulls' | 'tasks' | 'notes' | 'slack';

export const MODULE_IDS: ModuleId[] = ['email', 'agenda', 'jira', 'pulls', 'tasks', 'notes', 'slack'];

export type FieldType = 'text' | 'password' | 'url' | 'number' | 'select';

export interface FieldSpec {
  name: string;
  label: string;
  type: FieldType;
  /** Nunca volta para o cliente depois de gravado. */
  secret?: boolean;
  required?: boolean;
  placeholder?: string;
  help?: string;
  options?: { value: string; label: string }[];
  defaultValue?: string;
  /** Só aparece quando outro campo tem um destes valores. */
  showWhen?: { field: string; equals: string[] };
  /**
   * Campo que a conexão guarda mas o formulário nunca mostra — um refresh
   * token vindo do OAuth, por exemplo. Sem declará-lo, uma edição pela tela
   * gravaria a conexão sem ele e derrubaria o acesso; declarado e oculto, ele
   * é preservado e o cliente não consegue escrevê-lo.
   */
  hidden?: boolean;
}

export interface ModuleSpec {
  id: ModuleId;
  label: string;
  /** O que o painel mostra, em uma linha. */
  summary: string;
  /** Vários conectores (caixas de e-mail, agendas) ou um só. */
  multi: boolean;
  /** Funciona sem credencial nenhuma, então já vem ligado no primeiro login. */
  alwaysAvailable?: boolean;
  /** Passo a passo para obter a credencial, em linguagem de quem nunca viu. */
  instructions: string[];
  fields: FieldSpec[];
}

// Presets de IMAP/SMTP. Existem para que quem usa Gmail ou Outlook não precise
// procurar host e porta: escolhe o provedor e só preenche e-mail e senha.
export interface MailPreset {
  imapHost: string;
  imapPort: string;
  smtpHost: string;
  smtpPort: string;
}

export const MAIL_PRESETS: Record<string, MailPreset> = {
  gmail: { imapHost: 'imap.gmail.com', imapPort: '993', smtpHost: 'smtp.gmail.com', smtpPort: '465' },
  outlook: {
    imapHost: 'outlook.office365.com',
    imapPort: '993',
    smtpHost: 'smtp.office365.com',
    smtpPort: '587',
  },
  icloud: {
    imapHost: 'imap.mail.me.com',
    imapPort: '993',
    smtpHost: 'smtp.mail.me.com',
    smtpPort: '587',
  },
  yahoo: { imapHost: 'imap.mail.yahoo.com', imapPort: '993', smtpHost: 'smtp.mail.yahoo.com', smtpPort: '465' },
  fastmail: { imapHost: 'imap.fastmail.com', imapPort: '993', smtpHost: 'smtp.fastmail.com', smtpPort: '465' },
};

/** Preenche host e porta a partir do provedor escolhido, sem apagar o que a
 *  pessoa já digitou à mão. */
export function applyMailPreset(
  values: Record<string, string>,
): Record<string, string> {
  const preset = MAIL_PRESETS[values.preset ?? ''];
  if (!preset) return values;
  return { ...preset, ...values };
}

const MAIL_FIELDS: FieldSpec[] = [
  {
    name: 'preset',
    label: 'Provedor',
    type: 'select',
    required: true,
    defaultValue: 'gmail',
    options: [
      { value: 'gmail', label: 'Gmail' },
      { value: 'outlook', label: 'Outlook / Microsoft 365' },
      { value: 'icloud', label: 'iCloud' },
      { value: 'yahoo', label: 'Yahoo' },
      { value: 'fastmail', label: 'Fastmail' },
      { value: 'custom', label: 'Outro (IMAP manual)' },
    ],
  },
  { name: 'user', label: 'Endereço de e-mail', type: 'text', required: true, placeholder: 'voce@gmail.com' },
  {
    name: 'password',
    label: 'Senha de app',
    type: 'password',
    secret: true,
    required: true,
    help: 'A senha de app, não a senha da sua conta.',
  },
  {
    name: 'imapHost',
    label: 'Servidor IMAP',
    type: 'text',
    required: true,
    showWhen: { field: 'preset', equals: ['custom'] },
  },
  {
    name: 'imapPort',
    label: 'Porta IMAP',
    type: 'number',
    defaultValue: '993',
    showWhen: { field: 'preset', equals: ['custom'] },
  },
  {
    name: 'smtpHost',
    label: 'Servidor SMTP',
    type: 'text',
    help: 'Usado só para responder e-mails.',
    showWhen: { field: 'preset', equals: ['custom'] },
  },
  {
    name: 'smtpPort',
    label: 'Porta SMTP',
    type: 'number',
    defaultValue: '465',
    showWhen: { field: 'preset', equals: ['custom'] },
  },
];

export const MODULES: Record<ModuleId, ModuleSpec> = {
  email: {
    id: 'email',
    label: 'E-mail',
    summary: 'Caixa de entrada, responder, etiquetar e arquivar.',
    multi: true,
    instructions: [
      'Conecta por IMAP com senha de app — nenhum OAuth, nenhum cadastro de aplicativo.',
      'Gmail: ative a verificação em duas etapas e gere uma senha em myaccount.google.com/apppasswords.',
      'Outlook/Microsoft 365: gere em account.microsoft.com/security, em Opções de segurança avançadas.',
      'iCloud: gere em account.apple.com, na seção Segurança.',
      'Qualquer outro provedor IMAP funciona escolhendo "Outro" e preenchendo host e porta.',
    ],
    fields: MAIL_FIELDS,
  },
  agenda: {
    id: 'agenda',
    label: 'Agenda',
    // O resumo dizia "hoje e amanhã" enquanto a janela era de sete dias.
    // Agora o período é escolha de cada um, então ele não promete um número.
    summary: 'Compromissos no período que você escolher.',
    multi: true,
    instructions: [
      'Para contas Google, conecte pelo botão do Google: funciona com conta pessoal e corporativa, e não quebra quando o link muda.',
      'O link iCal serve para os demais provedores — Outlook, Apple, Fastmail, Nextcloud.',
      'Google Agenda: Configurações → clique na agenda à esquerda → "Integrar agenda" → "Endereço secreto no formato iCal" (termina em .ics).',
      'Outlook: Configurações → Agenda → Agendas compartilhadas → Publicar, e copie o link ICS.',
      'Em conta corporativa o administrador costuma bloquear o link iCal; nesse caso só a conexão pelo Google funciona.',
      'O painel lê os compromissos e cria blocos de foco após sua confirmação.',
      'Quantos dias aparecem é escolha sua, nos botões do próprio painel.',
    ],
    fields: [
      { name: 'provider', label: 'Origem', type: 'text', hidden: true, defaultValue: 'ics' },
      { name: 'account', label: 'Conta Google', type: 'text', hidden: true },
      { name: 'refreshToken', label: 'Token do Google', type: 'password', secret: true, hidden: true },
      { name: 'scope', label: 'Permissões do Google', type: 'text', hidden: true },
      { name: 'calendarIds', label: 'Agendas escolhidas', type: 'text', hidden: true },
      {
        name: 'icsUrl',
        label: 'URL do iCal (.ics)',
        type: 'url',
        secret: true,
        required: true,
        placeholder: 'https://calendar.google.com/calendar/ical/.../basic.ics',
        help: 'Copie o "Endereço secreto no formato iCal" — não o endereço da barra do navegador.',
        // Numa conexão do Google não existe link iCal para preencher.
        showWhen: { field: 'provider', equals: ['ics'] },
      },
    ],
  },
  jira: {
    id: 'jira',
    label: 'Jira',
    summary: 'Suas issues, em hierarquia, o que entregou hoje e menções.',
    multi: false,
    instructions: [
      'Precisa de um API token do Atlassian, que é gratuito.',
      'Gere em id.atlassian.com/manage-profile/security/api-tokens.',
      'O domínio é o começo da URL: em acme.atlassian.net, o domínio é "acme".',
    ],
    fields: [
      {
        name: 'cloud',
        label: 'Domínio Jira Cloud',
        type: 'text',
        required: true,
        placeholder: 'acme',
        help: 'Só o nome, ou a URL inteira — os dois funcionam.',
      },
      { name: 'email', label: 'E-mail da conta Atlassian', type: 'text', required: true },
      { name: 'token', label: 'API token', type: 'password', secret: true, required: true },
    ],
  },
  pulls: {
    id: 'pulls',
    label: 'Pull requests',
    summary: 'PRs abertos esperando por você.',
    multi: false,
    instructions: [
      'Precisa de um personal access token do GitHub, que é gratuito.',
      'Gere em github.com/settings/tokens.',
      'Escopo "repo" para repositórios privados; para só públicos, nenhum escopo basta.',
      'Os repositórios acompanhados são configurados no próprio painel.',
    ],
    fields: [
      { name: 'token', label: 'Personal access token', type: 'password', secret: true, required: true },
      {
        name: 'repos',
        label: 'Repositórios',
        type: 'text',
        placeholder: 'dono/repo, dono/outro',
        help: 'Separados por vírgula. Dá para editar depois direto no painel.',
      },
      // Edited only from the panel; hidden so a settings-form save keeps it.
      { name: 'repoAuthors', label: 'Autores acompanhados', type: 'text', hidden: true },
    ],
  },
  slack: {
    id: 'slack',
    label: 'Slack',
    summary: 'menções e mensagens diretas',
    multi: false,
    instructions: [
      'Clique em "Conectar com Slack" e autorize o acesso à sua conta.',
      'Se o workspace exigir aprovação de aplicativos, uma pessoa administradora talvez precise aprovar o app.',
      'A conexão é somente da sua conta e mostra menções e mensagens diretas não lidas.',
    ],
    fields: [
      { name: 'token', label: 'Token do Slack', type: 'password', secret: true, hidden: true },
      { name: 'userId', label: 'Usuário do Slack', type: 'text', hidden: true },
      { name: 'teamId', label: 'Workspace', type: 'text', hidden: true },
      { name: 'teamName', label: 'Nome do workspace', type: 'text', hidden: true },
      { name: 'scope', label: 'Permissões', type: 'text', hidden: true },
    ],
  },
  tasks: {
    id: 'tasks',
    label: 'Tarefas',
    summary: 'Lista de tarefas com subtarefas, prazo e prioridade.',
    multi: false,
    alwaysAvailable: true,
    instructions: [
      'O padrão guarda as tarefas no próprio banco da app: funciona na hora, sem credencial.',
      'Microsoft To Do só aparece se a CLI mstodo estiver instalada na máquina.',
    ],
    fields: [
      {
        name: 'provider',
        label: 'Onde guardar',
        type: 'select',
        required: true,
        defaultValue: 'local',
        options: [
          { value: 'local', label: 'Neste servidor (padrão)' },
          { value: 'mstodo', label: 'Microsoft To Do (CLI mstodo)' },
        ],
      },
      {
        name: 'clientId',
        label: 'Application (client) ID',
        type: 'text',
        showWhen: { field: 'provider', equals: ['mstodo'] },
      },
      {
        name: 'list',
        label: 'Nome da lista',
        type: 'text',
        showWhen: { field: 'provider', equals: ['mstodo'] },
      },
    ],
  },
  notes: {
    id: 'notes',
    label: 'Notas rápidas',
    summary: 'Bloco de notas com abas em Markdown, com cópia opcional no Google Drive.',
    multi: false,
    alwaysAvailable: true,
    instructions: [
      'Funciona sem credencial nenhuma: as notas ficam no banco da própria app.',
      'Conecte o Google Drive para ter uma cópia fora deste servidor. Cada nota vira um arquivo .md na pasta "daily-web — notas".',
      'A app só enxerga os arquivos que ela mesma criou no seu Drive — nada mais.',
      'Numa instalação nova, conectar a mesma conta traz as notas de volta.',
      'A cópia vai daqui para o Drive: editar o arquivo direto no Drive não altera a nota, e a próxima edição aqui o sobrescreve.',
      'As notas que já existiam antes de conectar sobem quando forem editadas.',
    ],
    // Nenhum campo visível: a conexão só nasce pelo botão do Google.
    fields: [
      { name: 'provider', label: 'Origem', type: 'text', hidden: true },
      { name: 'account', label: 'Conta Google', type: 'text', hidden: true },
      { name: 'refreshToken', label: 'Token do Google', type: 'password', secret: true, hidden: true },
    ],
  },
};

export function isModuleId(value: unknown): value is ModuleId {
  return typeof value === 'string' && (MODULE_IDS as string[]).includes(value);
}

/** Campos que o formulário deve mostrar para os valores atuais. Um campo com
 *  `showWhen` some quando a condição não bate — é o que faz o preset de e-mail
 *  esconder host e porta, e o Microsoft To Do esconder os seus campos. */
export function visibleFields(
  moduleId: ModuleId,
  values: Record<string, string>,
): FieldSpec[] {
  return MODULES[moduleId].fields.filter((field) => {
    if (field.hidden) return false;
    if (!field.showWhen) return true;
    const current = values[field.showWhen.field] ?? defaultsFor(moduleId)[field.showWhen.field] ?? '';
    return field.showWhen.equals.includes(current);
  });
}

export function defaultsFor(moduleId: ModuleId): Record<string, string> {
  const values: Record<string, string> = {};
  for (const field of MODULES[moduleId].fields) {
    if (field.defaultValue !== undefined) values[field.name] = field.defaultValue;
  }
  return values;
}

/** Erros de preenchimento, em linguagem de tela. Vazio quer dizer válido. */
export function validateValues(
  moduleId: ModuleId,
  values: Record<string, string>,
): string[] {
  const merged = { ...defaultsFor(moduleId), ...values };
  return visibleFields(moduleId, merged)
    .filter((field) => field.required && !(merged[field.name] ?? '').trim())
    .map((field) => `${field.label} é obrigatório`);
}
