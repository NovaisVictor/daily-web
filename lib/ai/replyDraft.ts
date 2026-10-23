import Anthropic from '@anthropic-ai/sdk';

const MODEL = 'claude-opus-5';

// O rascunho é curto e o usuário está esperando na tela: efeito "low" mantém
// a latência baixa sem perder o tom.
const EFFORT = 'low';

/**
 * The prompt used to name one person, which made every other user's draft
 * speak as them. The mailbox the reply goes out from is the only identity the
 * app knows for sure, so the draft is written on its behalf and never signs a
 * name it would have to guess.
 */
export function systemPrompt(sender: string): string {
  return [
    `Você escreve respostas de e-mail em nome de quem usa a caixa ${sender}.`,
    'Tom executivo: direto, objetivo, sem clichê corporativo. A informação principal vem na primeira frase.',
    'Responda no mesmo idioma do e-mail original.',
    'Não invente fatos, prazos ou compromissos que não estejam no e-mail ou na instrução.',
    'Não assine com um nome: a assinatura fica por conta de quem envia.',
    'Devolva apenas o corpo da resposta, em texto puro — sem assunto, sem cabeçalhos, sem o texto citado.',
  ].join(' ');
}

export class MissingApiKeyError extends Error {
  constructor() {
    super('ANTHROPIC_API_KEY não configurada');
    this.name = 'MissingApiKeyError';
  }
}

export interface DraftInput {
  /** The mailbox address the reply will be sent from. */
  sender: string;
  /** The author of the incoming e-mail, who receives the reply. */
  from: string;
  subject: string;
  body: string;
  instruction?: string;
}

export async function draftReply({ sender, from, subject, body, instruction }: DraftInput): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) throw new MissingApiKeyError();

  const prompt = [
    `De: ${from}`,
    `Assunto: ${subject}`,
    '',
    body,
    '',
    '---',
    instruction?.trim()
      ? `Escreva a resposta seguindo esta instrução: ${instruction.trim()}`
      : 'Escreva a resposta.',
  ].join('\n');

  const client = new Anthropic();
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 16000,
    output_config: { effort: EFFORT },
    system: systemPrompt(sender),
    messages: [{ role: 'user', content: prompt }],
  });

  return response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('\n')
    .trim();
}
