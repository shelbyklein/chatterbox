# Remove Agent Computer VM

Authorized by Shelby: remove the VM feature entirely. Linear execution in the current chat.

Scope: remove VM UI, Docker resources/controller, preview relays, handoff endpoints and tools from both shared-source consumers. Keep native ChatGPT computer-use configuration separate and unchanged. Preserve downloads, browser-profile volume and transcripts. Legacy chats receive a removal note and explicit thread-local VM-server disablement.

Checks: build both consumers; test MCP tool listing and legacy computer-only isolation; search for remaining runtime references; verify install. Stop only the named VM container, preserving its volume. Rollback via prior commits and saved app bundle.

Progress: implemented in Core 15f8e74; both Mac app builds pass. Runtime regression passes with both providers and replay across restart (/tmp/golem-runtime.4CxVtp). MCP regression verifies eight assistant tools, no VM tools, rejected start call, and an empty tool list for legacy computer-only sessions. Installed Chatterbox binary hash matches build; gracefully restarted chatterboxd. Live authenticated status/start/downloads/previews endpoints return 410. VM container stopped; profile volume and ~/Chatterbox/Computer/Downloads retained. Native plugin configuration unchanged. Golem UI build passed; install in progress. No physical mobile or manual visual interaction tested.
