import { describe, expect, it, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, cleanup, fireEvent, waitFor, within } from '@testing-library/react';
import { IntegrationsPanel } from '@/components/IntegrationsPanel';

interface ModuleFixture {
  module: string;
  label: string;
  summary: string;
  multi: boolean;
  enabled: boolean;
  configured: boolean;
  connections: unknown[];
}

function mod(over: Partial<ModuleFixture>): ModuleFixture {
  return {
    module: 'email',
    label: 'E-mail',
    summary: 'Caixa de entrada',
    multi: true,
    enabled: false,
    configured: false,
    connections: [],
    ...over,
  };
}

const EMPTY_MODULES = [
  mod({ module: 'email', label: 'E-mail', multi: true }),
  mod({ module: 'agenda', label: 'Agenda', multi: true }),
  mod({ module: 'jira', label: 'Jira', multi: false }),
  mod({ module: 'pulls', label: 'Pull requests', multi: false }),
  mod({ module: 'tasks', label: 'Tarefas', multi: false, enabled: true }),
  mod({ module: 'slack', label: 'Slack', multi: false }),
];

function payload(over: Record<string, unknown> = {}) {
  return {
    vaultReady: true,
    mstodoAvailable: false,
    googleConfigured: false,
    googleRedirectUri: 'https://exemplo.com/api/integrations/agenda/google/callback',
    slackConfigured: false,
    slackRedirectUri: 'https://exemplo.com/api/integrations/slack/callback',
    modules: EMPTY_MODULES,
    ...over,
  };
}

function mockFetch(handler: (url: string, init?: RequestInit) => unknown) {
  vi.spyOn(global, 'fetch').mockImplementation(
    async (input: RequestInfo | URL, init?: RequestInit) =>
      new Response(JSON.stringify(handler(String(input), init))),
  );
}

/** The form, the connections and the help live in the module's dialog, opened from its card. */
function openModule(
  label: string,
  button: 'Conectar' | 'Gerenciar' | 'Como conectar' = 'Conectar',
) {
  const card = screen.getByText(label, { selector: 'h3' }).closest('article') as HTMLElement;
  fireEvent.click(within(card).getByRole('button', { name: button }));
  return screen.getByRole('dialog');
}

beforeEach(() => {
  mockFetch(() => payload());
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('IntegrationsPanel', () => {
  it('lista todos os módulos, mesmo os não configurados', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('E-mail')).toBeInTheDocument());
    for (const label of ['Agenda', 'Jira', 'Pull requests', 'Tarefas']) {
      expect(screen.getByText(label)).toBeInTheDocument();
    }
  });

  // O cartão é só a manchete: logo, nome e as duas ações do print de referência.
  it('mostra um cartão por módulo com Conectar e Como conectar', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('E-mail')).toBeInTheDocument());

    // Ligado/Desligado é do diálogo; no cartão só aparece a tag de quem está conectado.
    expect(screen.queryByText(/^(Ligado|Desligado|Conectado)$/)).toBeNull();

    const cards = screen.getAllByRole('article');
    expect(cards).toHaveLength(EMPTY_MODULES.length);
    for (const card of cards) {
      expect(within(card).getByRole('button', { name: 'Conectar' })).toBeInTheDocument();
      expect(within(card).getByRole('button', { name: 'Como conectar' })).toBeInTheDocument();
    }
  });

  it('mostra a tag Conectado e troca Conectar por Gerenciar quando já existe uma conexão', async () => {
    const configured = EMPTY_MODULES.map((m) =>
      m.module === 'jira'
        ? {
            ...m,
            enabled: true,
            connections: [
              {
                id: 'jira-1',
                module: 'jira',
                label: 'Jira',
                visible: { cloud: 'acme' },
                secretsSet: ['token'],
                updatedAt: '2026-08-26',
                unreadable: false,
              },
            ],
          }
        : m,
    );
    mockFetch(() => payload({ modules: configured }));
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Jira', { selector: 'h3' })).toBeInTheDocument());

    const card = screen.getByText('Jira', { selector: 'h3' }).closest('article') as HTMLElement;
    expect(within(card).getByText('Conectado')).toBeInTheDocument();
    expect(within(card).getByRole('button', { name: 'Gerenciar' })).toBeEnabled();
    expect(within(card).queryByRole('button', { name: 'Conectar' })).toBeNull();
    expect(within(card).getByRole('button', { name: 'Como conectar' })).toBeDisabled();
  });

  it('avisa quando o servidor não tem chave para guardar credencial', async () => {
    mockFetch(() => payload({ vaultReady: false }));
    render(<IntegrationsPanel />);
    await waitFor(() =>
      expect(screen.getByRole('alert').textContent).toContain('DAILY_WEB_SECRET_KEY'),
    );
  });

  it('mostra o passo a passo de como obter a credencial', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Agenda')).toBeInTheDocument());

    const dialog = openModule('Agenda', 'Como conectar');
    expect(within(dialog).getByText(/Endereço secreto no formato iCal/)).toBeInTheDocument();
  });

  // O preset é o que torna a configuração de e-mail viável para quem não sabe
  // o host do próprio provedor.
  it('esconde host e porta quando o provedor é conhecido e revela no manual', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('E-mail')).toBeInTheDocument());
    fireEvent.click(screen.getAllByRole('button', { name: 'Conectar' })[0]);

    expect(screen.queryByLabelText(/Servidor IMAP/)).toBeNull();

    fireEvent.change(screen.getByLabelText(/Provedor/), { target: { value: 'custom' } });
    expect(screen.getByLabelText(/Servidor IMAP/)).toBeInTheDocument();
  });

  it('grava a conexão nova no módulo certo', async () => {
    const calls: { url: string; body: unknown }[] = [];
    mockFetch((url, init) => {
      if (init?.method === 'POST') {
        calls.push({ url, body: JSON.parse(String(init.body)) });
        return { modules: EMPTY_MODULES };
      }
      return payload();
    });

    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Agenda')).toBeInTheDocument());
    fireEvent.click(screen.getAllByRole('button', { name: 'Conectar' })[1]);

    fireEvent.change(screen.getByLabelText('Nome desta conexão'), {
      target: { value: 'Pessoal' },
    });
    fireEvent.change(screen.getByLabelText(/URL do iCal/), {
      target: { value: 'https://exemplo/a.ics' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(calls).toHaveLength(1));
    expect(calls[0].url).toBe('/api/integrations/agenda/connections');
    expect(calls[0].body).toEqual({
      label: 'Pessoal',
      values: { icsUrl: 'https://exemplo/a.ics' },
    });
  });

  it('mostra o resultado do teste de conexão sem tratar falha como erro da app', async () => {
    const configured = EMPTY_MODULES.map((m) =>
      m.module === 'jira'
        ? {
            ...m,
            enabled: true,
            configured: true,
            connections: [
              {
                id: 'jira-1',
                module: 'jira',
                label: 'Jira',
                visible: { cloud: 'acme' },
                secretsSet: ['token'],
                updatedAt: '2026-08-26',
                unreadable: false,
              },
            ],
          }
        : m,
    );
    mockFetch((url, init) => {
      if (init?.method === 'POST' && url.endsWith('/test')) {
        return { ok: false, message: 'Jira recusou o e-mail ou o API token' };
      }
      return payload({ modules: configured });
    });

    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Jira', { selector: 'h3' })).toBeInTheDocument());
    openModule('Jira', 'Gerenciar');
    fireEvent.click(await screen.findByRole('button', { name: 'Testar' }));

    await waitFor(() =>
      expect(screen.getByRole('status').textContent).toContain('recusou o e-mail'),
    );
  });

  // O segredo nunca volta do servidor; o campo precisa dizer que existe algo
  // guardado, senão quem edita o rótulo acha que apagou o token.
  it('avisa que o segredo está guardado ao editar', async () => {
    const configured = EMPTY_MODULES.map((m) =>
      m.module === 'jira'
        ? {
            ...m,
            configured: true,
            connections: [
              {
                id: 'jira-1',
                module: 'jira',
                label: 'Jira',
                visible: { cloud: 'acme', email: 'a@x.com' },
                secretsSet: ['token'],
                updatedAt: '2026-08-26',
                unreadable: false,
              },
            ],
          }
        : m,
    );
    mockFetch(() => payload({ modules: configured }));

    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Jira', { selector: 'h3' })).toBeInTheDocument());
    openModule('Jira', 'Gerenciar');
    fireEvent.click(await screen.findByRole('button', { name: 'Editar' }));

    expect(screen.getByLabelText(/API token/)).toHaveAttribute(
      'placeholder',
      expect.stringContaining('guardado'),
    );
  });

  it('oferece o botão do Google quando o servidor tem client OAuth', async () => {
    mockFetch(() => payload({ googleConfigured: true }));
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Agenda')).toBeInTheDocument());

    const dialog = openModule('Agenda');
    const link = within(dialog).getByRole('link', { name: 'Conectar' });
    expect(link).toHaveAttribute('href', '/api/integrations/agenda/google/start');
  });

  it('oferece conexão OAuth do Slack quando configurada no servidor', async () => {
    mockFetch(() => payload({ slackConfigured: true }));
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Slack')).toBeInTheDocument());
    const dialog = openModule('Slack');
    expect(within(dialog).getByRole('link', { name: 'Conectar' })).toHaveAttribute(
      'href',
      '/api/integrations/slack/start',
    );
  });

  // Oferecer um caminho que não existe é pior do que não oferecer; e quem
  // administra precisa saber exatamente qual URI registrar.
  it('sem client OAuth, esconde o botão e diz o que falta', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Agenda')).toBeInTheDocument());

    const dialog = openModule('Agenda');
    expect(within(dialog).queryByRole('link', { name: 'Conectar' })).toBeNull();
    expect(screen.getByText('GOOGLE_CLIENT_ID')).toBeInTheDocument();
    expect(
      screen.getByText('https://exemplo.com/api/integrations/agenda/google/callback'),
    ).toBeInTheDocument();
  });

  it('não mostra o liga/desliga no popup: conectar já liga o módulo', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Jira', { selector: 'h3' })).toBeInTheDocument());

    const dialog = openModule('Jira');
    expect(within(dialog).queryByRole('checkbox')).toBeNull();
    expect(within(dialog).queryByText(/^(Ligado|Desligado)$/)).toBeNull();
  });

  it('mantém o link iCal como alternativa quando o Google está disponível', async () => {
    mockFetch(() => payload({ googleConfigured: true }));
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Agenda')).toBeInTheDocument());

    const dialog = openModule('Agenda');
    fireEvent.click(within(dialog).getByRole('button', { name: 'Usar link iCal' }));
    expect(within(dialog).getByLabelText(/URL do iCal/)).toBeInTheDocument();
  });

  it('mostra o resultado que volta do retorno do Google', async () => {
    window.history.replaceState({}, '', '/tools?conectado=Google+Agenda+conectado');
    render(<IntegrationsPanel />);
    await waitFor(() =>
      expect(screen.getByRole('status').textContent).toContain('Google Agenda conectado'),
    );
    // A mensagem sai da URL para não reaparecer a cada recarga.
    expect(window.location.search).toBe('');
  });

  it('não oferece o Microsoft To Do quando a CLI não está instalada', async () => {
    render(<IntegrationsPanel />);
    await waitFor(() => expect(screen.getByText('Tarefas')).toBeInTheDocument());

    // Pelo cartão, não pelo índice: a posição muda quando um módulo entra.
    const dialog = openModule('Tarefas');

    const select = within(dialog).getByLabelText(/Onde guardar/) as HTMLSelectElement;
    const values = Array.from(select.options).map((o) => o.value);
    expect(values).toEqual(['local']);
  });
});
