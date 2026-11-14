import PlayGameIsland from './islands/PlayGameIsland';

// prestruct island registry. Components here run only in the browser, after
// the prerendered page hydrates; they are never executed by the SSR build.
export const islands = {
  'play-game': PlayGameIsland,
};
