// Importa a configuração que ficava em variáveis de ambiente e arquivos da
// máquina para as conexões de um usuário. Serve para quem já rodava a versão
// que dependia das CLIs e não quer redigitar token nenhum.
//
//   npm run import-machine -- <username>
//
// Só cria o que ainda não existe; rodar duas vezes não duplica nada. E-mail e
// agenda ficam de fora de propósito: eles autenticavam por OAuth e agora
// pedem senha de app e link iCal, que só a pessoa consegue gerar.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { findUserByUsername } from '@/lib/auth/users';
import {
  countConnections,
  saveConnection,
  type ModuleState,
} from '@/lib/vault/connections';
import { moduleStates } from '@/lib/vault/connections';
import { parseRepoList, serializeRepoList } from '@/lib/integrations/githubApi';

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

const [username] = process.argv.slice(2);
if (!username) fail('uso: npm run import-machine -- <username>');

const user = findUserByUsername(username);
if (!user) fail(`usuário ${username} não encontrado`);

function skipOrCreate(
  moduleId: 'jira' | 'pulls' | 'tasks',
  label: string,
  values: Record<string, string>,
): void {
  if (countConnections(user!.id, moduleId) > 0) {
    console.log(`· ${moduleId}: já existe, deixando como está`);
    return;
  }
  if (Object.values(values).every((v) => !v)) {
    console.log(`· ${moduleId}: nada no ambiente para importar`);
    return;
  }
  saveConnection(user!.id, moduleId, label, values);
  console.log(`✓ ${moduleId}: importado`);
}

// Os repositórios acompanhados viviam na config do ghpending.
function ghpendingRepos(): string {
  try {
    const text = readFileSync(
      path.join(os.homedir(), '.config', 'ghpending', 'config.toml'),
      'utf8',
    );
    const match = /^repos\s*=\s*\[([^\]]*)\]/m.exec(text);
    if (!match) return '';
    return serializeRepoList(
      parseRepoList(match[1].replace(/"/g, '')),
    );
  } catch {
    return '';
  }
}

skipOrCreate('jira', 'Jira', {
  cloud: process.env.JIRA_CLOUD ?? '',
  email: process.env.JIRA_EMAIL ?? '',
  token: process.env.JIRA_TOKEN ?? '',
});

skipOrCreate('pulls', 'GitHub', {
  token: process.env.GITHUB_TOKEN ?? '',
  repos: ghpendingRepos(),
});

skipOrCreate('tasks', 'Microsoft To Do', {
  provider: process.env.DAILY_TUI_TODO_CLIENT_ID ? 'mstodo' : '',
  clientId: process.env.DAILY_TUI_TODO_CLIENT_ID ?? '',
  list: process.env.DAILY_TUI_TODO_LIST ?? '',
});

const states: ModuleState[] = moduleStates(user.id);
console.log('\nestado dos módulos:');
for (const state of states) {
  const mark = state.enabled ? 'ligado ' : 'desligado';
  console.log(`  ${mark}  ${state.label}${state.configured ? '' : ' (sem conexão)'}`);
}
console.log('\nE-mail e agenda precisam ser conectados na tela /tools:');
console.log('  e-mail — senha de app do provedor');
console.log('  agenda — endereço secreto em formato iCal');
