/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Git short hash of the packed game content (CI sets it at export). */
  readonly VITE_CONTENT_HASH?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
