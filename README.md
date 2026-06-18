# Merken

A local-first macOS notes app for Obsidian-style vaults, with an Ollama-powered chat sidekick.

- Plain `.md` files on disk — your vault stays yours.
- Wikilink-aware editor (`[[note]]`).
- Background-indexed retrieval over the whole vault.
- Chat against your notes via a local Ollama model — no cloud, no keys.
- Tasks panel surfaces every `- [ ]` line across the vault.

## Build

```sh
./build.sh
open Merken.app
```

Requires macOS 13+ and Swift 5.9. Chat needs [Ollama](https://ollama.com) running locally (`ollama serve`).

## License

MIT
