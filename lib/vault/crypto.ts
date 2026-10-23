import { createCipheriv, createDecipheriv, randomBytes, hkdfSync } from 'node:crypto';

const ALGORITHM = 'aes-256-gcm';
const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;
const VERSION = 'v1';

// A chave é lida a cada chamada, não no import: assim trocar a variável (nos
// testes, ou num reload de serviço) tem efeito sem precisar recarregar o módulo.
function key(purpose?: string): Buffer {
  const raw = process.env.DAILY_WEB_SECRET_KEY;
  if (!raw) {
    throw new Error(
      'DAILY_WEB_SECRET_KEY não configurada — credenciais não podem ser guardadas',
    );
  }
  const parsed = Buffer.from(raw, 'base64');
  if (parsed.length !== KEY_BYTES) {
    throw new Error(
      `DAILY_WEB_SECRET_KEY precisa ter 32 bytes em base64 (recebeu ${parsed.length})`,
    );
  }
  return purpose ? Buffer.from(hkdfSync('sha256', parsed, 'daily-web', purpose, KEY_BYTES)) : parsed;
}

export function isVaultConfigured(): boolean {
  try {
    key();
    return true;
  } catch {
    return false;
  }
}

// Formato: v1.<iv>.<tag>.<ciphertext>, tudo base64url. O prefixo de versão
// existe para permitir trocar o algoritmo depois sem adivinhar o formato de
// registros antigos.
export function encrypt(plaintext: string, purpose?: string): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, key(purpose), iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [
    VERSION,
    iv.toString('base64url'),
    tag.toString('base64url'),
    ciphertext.toString('base64url'),
  ].join('.');
}

export function decrypt(payload: string, purpose?: string): string {
  const [version, ivB64, tagB64, dataB64] = payload.split('.');
  if (version !== VERSION || !ivB64 || !tagB64 || dataB64 === undefined) {
    throw new Error('credencial em formato desconhecido');
  }
  const tag = Buffer.from(tagB64, 'base64url');
  if (tag.length !== TAG_BYTES) throw new Error('credencial corrompida');

  const decipher = createDecipheriv(ALGORITHM, key(purpose), Buffer.from(ivB64, 'base64url'));
  decipher.setAuthTag(tag);
  // GCM autentica: se o texto foi adulterado ou a chave é outra, final() lança
  // em vez de devolver bytes sem sentido.
  return Buffer.concat([
    decipher.update(Buffer.from(dataB64, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}
