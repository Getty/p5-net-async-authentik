# CLAUDE.md

Net::Async::Authentik — IO::Async-based client for authentik: the async twin of `WWW::Authentik` (`p5-www-authentik`), same API surface with `_f` suffixes returning Futures, a structural sibling of `Net::Async::Keycloak`. Moo-based on `IO::Async::Notifier`; released to CPAN via Dist::Zilla `[@Author::GETTY]`.

The sync twin leads: an API lands in `p5-www-authentik` first and is mirrored here. Skeleton state: nothing is implemented yet; the design lives in `p5-www-authentik/docs/superpowers/specs/`, the work is on the karr board.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
principle and lane are in `.claude/rules/net-async-authentik-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-async-authentik-worker` (default) |
| Write/extend tests | `net-async-authentik-test-writer` |
| Commits, `Changes`, card → done, pre-release audit | `net-async-authentik-release-manager` |
| Write/maintain POD | `net-async-authentik-doc-writer` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the main
agent delegates rather than loading them. Skill sources live under `.claude/skills/`.

## Commands

```bash
prove -lr t          # full test suite (recursive; live tests skip by default)
dzil build           # build the distribution
dzil test            # test via Dist::Zilla
```

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
