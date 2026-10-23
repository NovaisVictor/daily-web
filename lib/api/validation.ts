import type { NotePaper, PinColor, TaskPriority } from '@/lib/types';
import { NOTE_PAPERS, PIN_COLORS } from '@/lib/taskBoard';
import type { Recur } from '@/lib/tasks/types';

const ID_PATTERN = /^[A-Za-z0-9_-]+$/;

// Ids de tarefa não são nossos: vêm do provedor. Os do Microsoft Graph são
// base64 e trazem `=` de preenchimento, que o charset acima recusava — na
// prática isso reprovava *todos* eles e deixava concluir, editar e apagar
// quebrados para quem usa Microsoft To Do. Os do provedor local são UUID.
//
// O risco que a validação existe para conter é outro: o id vira argumento
// posicional de uma CLI via execFile, e um id começando com "-" seria lido
// como flag. Esse é o guard que importa, e ele continua.
const TASK_ID_PATTERN = /^[A-Za-z0-9_\-=+/]+$/;
const TASK_ID_MAX_LENGTH = 512;
const FOLDER_PATTERN = /^[A-Za-z0-9 _\-/]+$/;
const REPO_PATTERN = /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/;
const VALID_TASK_PRIORITIES: TaskPriority[] = ['low', 'normal', 'high'];
const VALID_RECURS: Recur[] = ['none', 'daily', 'weekly', 'monthly'];

// Uma conta não é mais validada por formato: ela é um id de conexão, e a
// checagem que importa é de posse, feita em requireConnection contra o dono
// da sessão. Validar o formato aqui daria a impressão de proteção sem
// impedir que alguém usasse a conexão de outra pessoa.

export function isValidEmailId(value: unknown): value is string {
  return typeof value === 'string' && ID_PATTERN.test(value) && !value.startsWith('-');
}

export function isValidFolder(value: unknown): value is string {
  return typeof value === 'string' && FOLDER_PATTERN.test(value) && !value.startsWith('-');
}

export function isValidTaskId(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    value.length <= TASK_ID_MAX_LENGTH &&
    TASK_ID_PATTERN.test(value) &&
    !value.startsWith('-')
  );
}

export function isValidTaskPriority(value: unknown): value is TaskPriority {
  return typeof value === 'string' && (VALID_TASK_PRIORITIES as string[]).includes(value);
}

export function isValidRecur(value: unknown): value is Recur {
  return typeof value === 'string' && (VALID_RECURS as string[]).includes(value);
}

// The database has no CHECK on the colours, so a new one costs no table
// rebuild; this list is the guard instead, on the way in.
export function isNotePaper(value: unknown): value is NotePaper {
  return typeof value === 'string' && (NOTE_PAPERS as string[]).includes(value);
}

export function isPinColor(value: unknown): value is PinColor {
  return typeof value === 'string' && (PIN_COLORS as string[]).includes(value);
}

// Guarda mínima para valores de texto livre (ex.: title) que acabam como
// argumento posicional ou valor de flag em uma chamada execFile. Não aplica
// o charset restrito de isValidTaskId (title precisa aceitar espaços,
// acentos, pontuação) — apenas recusa um "-" inicial, que um parser de CLI
// poderia interpretar como início de outra flag.
export function isSafePositionalValue(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && !value.startsWith('-');
}

export function isValidRepo(value: unknown): value is string {
  return typeof value === 'string' && REPO_PATTERN.test(value);
}
