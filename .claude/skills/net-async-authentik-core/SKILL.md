---
name: net-async-authentik-core
description: Use when working on Net::Async::Authentik — the IO::Async/Future client for authentik's OIDC endpoints and REST API (v3), its module layout, error classes, or its tests.
---

# Net::Async::Authentik core

IO::Async-based client for authentik, the async twin of `WWW::Authentik`
(`~/dev/p5-www-authentik`), a structural sibling of `Net::Async::Keycloak`
(`~/dev/p5-net-async-keycloak`). **Skeleton state: nothing is implemented yet.** The design
is the sync twin's `docs/superpowers/specs/2026-10-04-www-authentik-design.md` (approved);
where it and the map below disagree, the design wins.

## Planned module map

- `Net::Async::Authentik` — Moo class extending `IO::Async::Notifier`: `base_url`, optional
  `application` (slug), optional API token; lazy `http` (`Net::Async::HTTP`, added as
  child), lazy `oidc` and `api`.
- `Net::Async::Authentik::OIDC` — discovery, JWKS, token verification, userinfo,
  introspection, token and device endpoints.
- `Net::Async::Authentik::API` — REST API v3, every method as `_f`, `ensure_*_f` with
  `WWW::Authentik::Diff`.
- `Net::Async::Authentik::Error` — base; `::Validation`, `::Network`, `::API`, one package
  per file.

## Invariants

- **The sync twin leads.** Every public method here exists in `WWW::Authentik` under the
  same name plus `_f`. Do not invent API here; if the twin lacks it, ticket the twin.
- **This dist depends on `WWW::Authentik`** for `build_request`/`read_response` and
  `Diff`, as `Net::Async::Keycloak` depends on `WWW::Keycloak`. Everything with I/O is
  written here.
- **Every method returns a Future and never blocks.** No `->get` in library code, no
  synchronous HTTP client.
- **Notifier construction.** `IO::Async::Notifier->new` hands every key to `configure`,
  which croaks on unknown keys — strip own attributes in `FOREIGNBUILDARGS`, as
  `Net::Async::Keycloak` does.
- **authentik facts are verified, not remembered** — see the twin's core skill; the same
  rule applies here.
- **Live tests are opt-in** (`AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=…`). A default
  `prove -lr t` passes with them skipped.
