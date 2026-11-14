// Ambient declaration for prestruct's JS islands engine. Keep this file a
// script (no top-level import/export): a module-scoped `declare module` would
// be treated as an augmentation of the untyped JS file instead of a
// declaration for it.
declare module 'prestruct/islands' {
  export function mountIslands(registry?: Record<string, () => unknown>): void;
}

declare namespace JSX {
  interface IntrinsicElements {
    'pre-island': {
      'data-pre-island'?: string;
      'data-pre-load'?: 'eager' | 'visible' | 'idle';
      children?: unknown;
    };
  }
}
