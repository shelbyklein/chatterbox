# Snippets host

Small web artifacts published from Chatterbox (`bin/snippet`, the Publish menu on HTML pages)
at https://snippets.shelbyklein.com. Runs on the Beelink from `/srv/projects/snippets`:

- `site/`: what's published, mirroring where files live in Chatterbox
  (`studio/<studio>/…`, `project/<repo>/…`, `chat/<folder>/…`; `private/…` for private ones).
- `deploy/`: these files. Caddy serves `site/` read-only on `127.0.0.1:3120`; a dedicated
  Cloudflare tunnel (`snippets`, 9f038e77-125d-4b4f-937c-e9eb88382045) publishes it.
  `deploy/tunnel/credentials.json` stays on the Beelink only; never commit it.

Start or update, on the Beelink from `/srv/projects/snippets/deploy`:

    docker compose -f compose.yaml -f tunnel-compose.yaml up -d

## Private snippets

`/private/…` answers 403 until a Cloudflare Access application protects
`snippets.shelbyklein.com/private` (allow only Shelby's Google account). After that, replace
`private.caddy` with the header check its comment shows and restart the stack.
