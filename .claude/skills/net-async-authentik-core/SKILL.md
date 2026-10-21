---
name: net-async-authentik-core
description: Use when working on Net::Async::Authentik — the IO::Async/Future client for authentik's OIDC endpoints and REST API (v3), its module layout, error classes, or its tests.
---

# net-async-authentik — Kern

IO::Async-based client for authentik, the async twin of `WWW::Authentik`
(`~/dev/p5-www-authentik`), a structural sibling of `Net::Async::Keycloak`
(`~/dev/p5-net-async-keycloak`). The design is fixed in the twin's
`docs/superpowers/specs/2026-10-04-www-authentik-design.md`, the plan for this repo is
`docs/superpowers/plans/2026-10-04-net-async-authentik-phase-1.md`; where they and the
map below disagree, the design wins.

## The delegation model — why the main agent delegates

Four roles split the work: worker (implement, refactor, debug), test-writer,
release-manager (commit, `Changes`, card → done), doc-writer (POD). They get the skills
force-loaded via `briefing.skills`; the orchestrating main agent gets no briefing and
delegates everything behavior-relevant. Reason: only the briefed agents see the
sync/async twin invariant and the `WWW::Authentik` dependency contract in context, and an
unbriefed hand inside `lib/` would break exactly those. Which task goes to which role
stands in the rules file.

## Architecture — the layers and who calls whom

The facade owns exactly one `Net::Async::HTTP` and hands it down.

```
lib/Net/Async/Authentik.pm           # facade: attributes, the HTTP child, oidc/api
lib/Net/Async/Authentik/OIDC.pm      # discovery, JWKS, verification, grants, device flow
lib/Net/Async/Authentik/API.pm       # REST v3: call_f, _paged_f, resolve_f, ensure_*_f
lib/Net/Async/Authentik/Role/HTTP.pm # send_request_f, fail_validation, pairs_or_fail
lib/Net/Async/Authentik/Error*.pm    # base and the three subclasses, one per file
```

The facade is Moo on `IO::Async::Notifier`: `base_url` (required, trailing slashes
removed), optional `application` (slug), `client_id`, `token`; lazy `http`, `oidc`, `api`.
`http` is a **child notifier** (user agent `Net-Async-Authentik/<version>`,
`max_redirects => 0`, `fail_on_error => 0`, `timeout => 30`); an injected `http` is used
but **not** adopted as a child.

One request: caller → `oidc`/`api` method → `send_request_f` → `build_request` (sync
role) → `Net::Async::HTTP` → answer → `read_response` (sync role) → `{ status, data,
location, content }`. The async role is composed **before** the sync one, so its error
classes win. `oidc` and `api` are built even without a slug or a token — a missing
attribute becomes a failed future only when a method is called. `for_application($slug)`
builds a second facade over the same `base_url`, `http` and token, without the
`client_id`, which belongs to the provider of the one application.

## Vocabulary

- **application slug** — the OIDC address of one application: `/application/o/<slug>/`
  carries discovery and JWKS; token, device and userinfo endpoints are instance-wide.
- **provider** — the OAuth2 provider inside an application; its `client_id` is the
  audience a token is checked against.
- **issuer_mode** — `per_provider` (authentik's default) issues tokens under
  `<application_url>/`, so the issuer names the application; `global` issues them under
  the bare instance URL, the same for every application — then the audience, the
  `client_id`, alone tells two applications apart.
- **`type`** — a heuristic, not a claim: an access token carries a `scope` claim, an ID
  token does not, and authentik puts no `typ` into the JOSE header.
- **`changed`** — the second key of an `ensure_*_f` result: `created`, `updated` or `''`
  for a run that changed nothing.
- **resolve** — names into identifiers: one fixed identifier shape per field (a UUID or
  a run of digits), everything else is a name to look up.

## Invariants

- **The sync twin leads.** Every public method here exists in `WWW::Authentik` under the
  same name plus `_f`. Do not invent API here; if the twin lacks it, ticket the twin.
- **This dist depends on `WWW::Authentik`** for `build_request`/`read_response` and
  `Diff`, as `Net::Async::Keycloak` depends on `WWW::Keycloak`; everything with I/O is
  written here.
- **The error classes are both worlds at once.** `Net::Async::Authentik::Error` extends
  `WWW::Authentik::Error`, and every subclass extends its sync counterpart too, so code
  that catches `WWW::Authentik::Error::API` catches the errors of this dist as well.
- **Every method returns a Future and never blocks.** No `->get` in library code, no
  synchronous HTTP client.
- **Nothing throws, not even a wrong argument.** A validation error fails the future, so
  one `else` catches it next to a refused request. Two things sit outside that: the
  constructor croaks when `base_url` is missing, and `application_url`/`issuer` throw.
- **A dropped future still does the work.** The async sub has begun and the request is
  held by the HTTP client, so authentik is written to and the answer goes nowhere, with a
  "lost its returning future" warning. The POD says: hold it, or `->retain` it.
- **`Net::Async::HTTP` needs none of LWP's workarounds.** It does not announce the `TE`
  connection token, so authentik answers every request; `max_redirects => 0` hands a 302
  back as an answer; `fail_on_error => 0` lets `read_response` make the error.
- **Notifier construction.** `IO::Async::Notifier->new` hands every key to `configure`,
  which croaks on unknown keys — strip own attributes in `FOREIGNBUILDARGS`.
- **authentik facts are verified, not remembered** — see the twin's core skill.
- **Live tests are opt-in** (`AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=…`). A default
  `prove -lr t` passes with them skipped.

## Hazards — the seams that break silently

- **A future still pending at exit can take the interpreter down.** `double free or
  corruption`, segfault, in global destruction after the program's own work is done, so
  the damage is the exit status rather than lost data. It is a defect in
  Future::AsyncAwait: an `async sub` suspended at exit whose saved frame holds a
  reference argument corrupts the heap. Holding the future and `->retain` do not help —
  letting it finish does.
- **An odd argument list is the cheapest way into that crash.** `pairs_or_fail` in
  `Role::HTTP` checks the shape of the argument list *before* a hash is built from it,
  and fails the future when the list does not make pairs.
- **The HTTP client dies when it is in no loop.** `send_request_f` catches that and fails
  the future with a network error whose message says "was the Net::Async::Authentik added
  to a loop?". A refused connection arrives as plain strings, a timeout as
  `('Timed out', 'timeout')` — both become a `Error::Network` object.
- **The REST API answers a path without a trailing slash with 404**, and a 3xx there is
  an error, not an answer: `call_f` fails it with `Error::API` and names the `Location`,
  because the REST API never redirects itself — a proxy, a login page or a wrong
  `base_url` sits in front of it. Below 400 everything is an answer, including the 302
  where authentik wants a browser.
- **A duplicate is 400 with a field error, a refused token is 403.** There is no 409 and
  no `is_conflict`; the field errors sit in `field_errors`, nested ones flattened.
- **The keys are shared, the fetch is not.** Twenty concurrent `verify_token_f` calls
  cause one discovery and (for an unknown `kid`) one extra key fetch; every caller gets
  its own cancellable view, so cancelling one does not take the fetch down. A rotated key
  triggers a re-fetch only for a `kid_keys lookup failed`, and not more often than
  `jwks_min_age` (60 s) allows.
- **Stage names are unique across all types.** `ensure_stage_f` refuses a name that
  belongs to another type instead of creating a second one.
- **`ensure_token_f` cannot set `expires`** — authentik ignores it and takes the expiry
  from the instance setting `default_token_duration`. A password and a token key are set
  only at creation, so a second run does not reset them.
- **`ensure_oauth2_provider_f` needs `grant_types` to create one** — authentik stores an
  empty list, and such a provider answers every token request with `invalid_grant`.
- **`scopes => undef` is a mistake, not a wish.** `resolve_f` refuses it; an empty list
  takes every mapping away.

## Commands

The sync distribution has to be on the path for every run:

```bash
export PERL5LIB=$HOME/dev/p5-www-authentik/lib
prove -lr t                     # full suite (recursive; live suite skips itself)
prove -lv t/70-async.t         # one file
dzil test --all                 # with the author and release tests
dzil build                      # build the distribution
AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=http://127.0.0.1:9000 AUTHENTIK_TOKEN=... \
  prove -lv t/90-live-authentik.t
```

`prove -lr t` is recursive on purpose — plain `prove -l t/` silently skips tests in subdirectories.

## The suite and the harness

`t/lib/FakeAuthentik.pm` is the in-memory authentik — a copy of the sync dist's, and
`t/00-load.t` fails when the two drift apart. `t/lib/FakeHTTP.pm` is the
`Net::Async::HTTP` stand-in, `t/lib/AuthentikExecutor.pm` drives the flow executor the
way a browser would, `t/authentik/` holds a throwaway instance to test against, and
`docs/future-asyncawait-0.71-crash.pl` reproduces the exit crash without this dist.

The tests: `t/00-load.t` (modules load), `t/20-errors.t` (the error classes),
`t/40-facade.t` (facade and sub-clients), `t/50-api.t` (REST v3, pagination),
`t/51-api-ensure.t` (`ensure_*_f`), `t/52-api-resolve.t` (names to identifiers),
`t/60-oidc.t` (discovery, JWKS, verification), `t/70-async.t` (what only goes wrong
asynchronously), `t/90-live-authentik.t` (the live suite).

## Boundaries

- **This repo holds the I/O, the sync distribution holds the semantics.** `build_request`,
  `read_response`, `flatten_field_errors`, `Diff`, `resolvable_fields` and the two
  identifier patterns are imported from the sync dist, not copied.
- **The identity provider itself is authentik's** — flows, stages, expressions and the
  token shapes are its business; this client speaks to them. **`Airlock`
  (`~/dev/p5-airlock`) is a consumer**, not a dependency.
