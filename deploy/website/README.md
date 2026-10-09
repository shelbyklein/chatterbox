# Website host

The Chatterbox website (`website/`) at https://chatterbox.shelbyklein.com. Runs on the Beelink from
`/srv/projects/chatterbox-site`, the same way as snippets:

- `site/`: a copy of `website/`.
- `deploy/`: these files. Caddy serves `site/` read-only on `127.0.0.1:3130`; a dedicated Cloudflare tunnel
  (`chatterbox-site`, 9acaf97c-c37a-459b-8a78-26becc1baffa) publishes it. `deploy/tunnel/credentials.json`
  stays on the Beelink only; never commit it.

Publish changes to `website/` from this repo (no restart needed):

    deploy/website/publish.sh

Start or update the stack, on the Beelink from `/srv/projects/chatterbox-site/deploy`:

    docker compose -f compose.yaml -f tunnel-compose.yaml up -d

DNS: `chatterbox.shelbyklein.com` is a CNAME to this tunnel. If it ever needs re-creating, pass a config that names
this tunnel; with the default `~/.cloudflared/config.yml`, `cloudflared tunnel route dns` routes to `agentos` instead:

    printf 'tunnel: 9acaf97c-c37a-459b-8a78-26becc1baffa\n' > /tmp/route.yml
    cloudflared tunnel --config /tmp/route.yml route dns --overwrite-dns 9acaf97c-c37a-459b-8a78-26becc1baffa chatterbox.shelbyklein.com
