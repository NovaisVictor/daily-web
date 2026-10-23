import { useId } from 'react';
import type { PinColor } from '@/lib/taskBoard';

/**
 * A plastic pushpin seen from the side, leaning right with its needle in the
 * paper: a cylinder head, a narrowing neck, a flared collar and a steel
 * needle. Colour comes from `--pin`, set per `data-pin` in globals.css, and
 * every shade is derived from it, so a new colour is one token.
 */
export function PushPin({ color }: { color: PinColor }) {
  // Gradient ids are document-global; two pins sharing one would both paint
  // with whichever was defined first.
  const id = useId();
  const body = `${id}-body`;
  const top = `${id}-top`;
  const steel = `${id}-steel`;
  const shadow = `${id}-shadow`;

  return (
    <svg className="postit-pin" data-pin={color} viewBox="0 0 56 58" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id={body} x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" style={{ stopColor: 'var(--pin-shade)' }} />
          <stop offset="0.3" style={{ stopColor: 'var(--pin)' }} />
          <stop offset="0.52" style={{ stopColor: 'var(--pin-light)' }} />
          <stop offset="0.7" style={{ stopColor: 'var(--pin)' }} />
          <stop offset="1" style={{ stopColor: 'var(--pin-shade)' }} />
        </linearGradient>
        <radialGradient id={top} cx="0.4" cy="0.35" r="0.75">
          <stop offset="0" style={{ stopColor: 'var(--pin-light)' }} />
          <stop offset="1" style={{ stopColor: 'var(--pin)' }} />
        </radialGradient>
        <linearGradient id={steel} x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stopColor="#6b7280" />
          <stop offset="0.5" stopColor="#e5e7eb" />
          <stop offset="1" stopColor="#4b5563" />
        </linearGradient>
        {/* A soft-edged shadow from a gradient rather than a blur filter: a
            filter per pin is re-rasterised whenever a note moves. */}
        <radialGradient id={shadow}>
          <stop offset="0" style={{ stopColor: 'var(--postit-shadow)' }} />
          <stop offset="1" style={{ stopColor: 'var(--postit-shadow)', stopOpacity: 0 }} />
        </radialGradient>
      </defs>

      {/* The shadow lies on the paper, so it is not rotated with the pin. */}
      <ellipse cx="33" cy="48" rx="11" ry="4.5" fill={`url(#${shadow})`} />
      <path className="postit-pin-shadow" d="M18 53 L29 48" strokeWidth="1.4" strokeLinecap="round" />

      <g transform="rotate(24 18 54)">
        <path d="M18 39 L18 54" stroke={`url(#${steel})`} strokeWidth="1.9" strokeLinecap="round" />
        <ellipse cx="18" cy="37.5" rx="8.5" ry="2.8" fill={`url(#${body})`} />
        <path d="M11.5 22 Q15 30 14.5 37 L21.5 37 Q21 30 24.5 22 Z" fill={`url(#${body})`} />
        <path className="postit-pin-head" d="M7 11 L7 21 A11 3.6 0 0 0 29 21 L29 11 Z" fill={`url(#${body})`} />
        <ellipse className="postit-pin-head" cx="18" cy="11" rx="11" ry="3.6" fill={`url(#${top})`} />
        {/* Specular highlights: the gloss is what reads as plastic. */}
        <ellipse cx="13" cy="15.5" rx="1.6" ry="3.6" fill="white" opacity="0.55" />
        <ellipse cx="14.5" cy="10.2" rx="4" ry="1.1" fill="white" opacity="0.6" />
        <ellipse cx="16.2" cy="27" rx="0.9" ry="3" fill="white" opacity="0.35" />
      </g>
    </svg>
  );
}
