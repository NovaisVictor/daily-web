import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { NOTE_PAPERS } from '@/lib/taskBoard';

// The note's ink is fixed per theme while the paper is chosen per task, so
// every pair is checked here against the stylesheet itself: a token tweaked
// in globals.css that drops a pair below AA fails the suite, not a person
// squinting at a grey note.

const css = readFileSync(path.resolve(__dirname, '../../app/globals.css'), 'utf8').replace(
  /\/\*[\s\S]*?\*\//g,
  '',
);

interface Block {
  selector: string;
  declarations: Map<string, string>;
}

/** Every rule block with its own declarations and the selectors around it,
 *  so `@media (…) { :root.x { … } }` reads as one path. */
function blocks(source: string): Block[] {
  const found: Block[] = [];
  const stack: { selector: string; own: string }[] = [];
  let buffer = '';
  for (const char of source) {
    if (char === '{') {
      stack.push({ selector: buffer.trim(), own: '' });
      buffer = '';
    } else if (char === '}') {
      const block = stack.pop();
      if (!block) continue;
      block.own += buffer;
      buffer = '';
      const declarations = new Map<string, string>();
      for (const part of block.own.split(';')) {
        const index = part.indexOf(':');
        if (index > 0) declarations.set(part.slice(0, index).trim(), part.slice(index + 1).trim());
      }
      found.push({
        selector: [...stack.map((b) => b.selector), block.selector].join(' '),
        declarations,
      });
    } else if (char === ';' && stack.length > 0) {
      stack[stack.length - 1].own += buffer + ';';
      buffer = '';
    } else {
      buffer += char;
    }
  }
  return found;
}

const all = blocks(css);
const themes = all.filter((b) => b.declarations.has('--postit-ink'));
const palette = new Map<string, string>();
for (const block of all) {
  for (const [name, value] of block.declarations) if (name.startsWith('--ctp-')) palette.set(name, value);
}

function resolve(value: string): string {
  const reference = /^var\((--[\w-]+)\)$/.exec(value);
  if (!reference) return value;
  const target = palette.get(reference[1]);
  if (!target) throw new Error(`token sem valor: ${reference[1]}`);
  return resolve(target);
}

type Oklch = [number, number, number];

function parseOklch(value: string): Oklch {
  const match = /^oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)$/.exec(resolve(value));
  if (!match) throw new Error(`não é oklch: ${value}`);
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

/** WCAG relative luminance from OKLCH, through OKLab and linear sRGB. */
function luminance([l, c, h]: Oklch): number {
  const a = c * Math.cos((h * Math.PI) / 180);
  const b = c * Math.sin((h * Math.PI) / 180);
  const lp = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const mp = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const sp = (l - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const clamp = (x: number) => Math.min(1, Math.max(0, x));
  const r = clamp(4.0767416621 * lp - 3.3077115913 * mp + 0.2309699292 * sp);
  const g = clamp(-1.2684380046 * lp + 2.6097574011 * mp - 0.3413193965 * sp);
  const bl = clamp(-0.0041960863 * lp - 0.7034186147 * mp + 1.707614701 * sp);
  return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
}

function contrast(x: Oklch, y: Oklch): number {
  const [hi, lo] = [luminance(x), luminance(y)].sort((p, q) => q - p);
  return (hi + 0.05) / (lo + 0.05);
}

describe('contraste da tinta das notas em cada papel', () => {
  it('encontra os blocos de tema que definem as notas: claro, escuro duas vezes, catppuccin duas vezes', () => {
    expect(themes).toHaveLength(5);
  });

  // Dracula não define papel: herda o do escuro, que já está coberto acima.
  it('o dracula não redefine as notas', () => {
    const dracula = all.filter((b) => b.selector.includes("data-backdrop='dracula'"));
    expect(dracula.length).toBeGreaterThan(0);
    for (const block of dracula) {
      expect([...block.declarations.keys()].some((k) => k.startsWith('--postit-'))).toBe(false);
    }
  });

  for (const theme of themes) {
    for (const paper of NOTE_PAPERS) {
      it(`${theme.selector}: tinta e tinta média ≥ 4.5:1 no papel ${paper}, até a base do degradê`, () => {
        const token = theme.declarations.get(`--postit-${paper}`);
        expect(token, `--postit-${paper} em ${theme.selector}`).toBeDefined();
        const [l, c, h] = parseOklch(token!);
        // The note darkens toward its bottom edge by 0.035 of lightness
        // (.postit's gradient); text there is the worst case.
        const bottom: Oklch = [l - 0.035, c, h];
        for (const ink of ['--postit-ink', '--postit-ink-mid']) {
          const inkColour = parseOklch(theme.declarations.get(ink)!);
          expect(contrast(inkColour, [l, c, h]), `${ink} no topo`).toBeGreaterThanOrEqual(4.5);
          expect(contrast(inkColour, bottom), `${ink} na base`).toBeGreaterThanOrEqual(4.5);
        }
      });
    }
  }

  it('todo papel da paleta tem a sua regra [data-paper] no estilo da nota', () => {
    for (const paper of NOTE_PAPERS.filter((p) => p !== 'yellow')) {
      expect(css).toContain(`.postit[data-paper='${paper}']`);
    }
    // Yellow is the default every note starts from.
    expect(css).toMatch(/\.postit,\s*\.paper-swatch,\s*\.paper-dot\s*\{\s*--postit-paper: var\(--postit-yellow\)/);
  });

  it('o conversor bate com valores conhecidos', () => {
    expect(contrast([1, 0, 0], [0, 0, 0])).toBeCloseTo(21, 1);
    expect(luminance([0.6279553606145516, 0.25768330773615683, 29.2338851923426])).toBeCloseTo(0.2126, 2);
  });
});
