# Net::Async::Authentik Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Net::Async::Authentik` phase 1: the asynchronous twin of `WWW::Authentik` on `IO::Async` and `Future`, every public method with `_f`, same classes, same errors, same behavior against the same authentik.

**Architecture:** Moo classes; the facade extends `IO::Async::Notifier` and holds a `Net::Async::HTTP` as a child node. What is not I/O comes from the sync dist and is not copied: `WWW::Authentik::Role::HTTP` provides `build_request`, `read_response` and `flatten_field_errors`, `WWW::Authentik::Diff` the comparison, `WWW::Authentik::API->resolvable_fields` the name resolution table. Sending happens here, via `Net::Async::Authentik::Role::HTTP`, which is composed before the sync role and overrides its error class methods.

**Tech Stack:** Perl 5.20+, Moo, IO::Async, Future, Future::AsyncAwait, Net::Async::HTTP, Types::Standard, WWW::Authentik. Dist::Zilla with `[@Author::GETTY]`.

**Spec:** the sync dist's, `~/dev/p5-www-authentik/docs/superpowers/specs/2026-10-04-www-authentik-design.md` (approved, with sections 12 and 13). Section 9 describes this twin.

## What `Net::Async::HTTP` does differently from LWP

Checked against the running authentik 2026.8.3, not carried over from the sync build. The four
hazards from section 13 of the spec look different here:

| Hazard of the sync dist | `Net::Async::HTTP` 0.50 |
|---|---|
| LWP announces `TE`, authentik leaves every second request unanswered | **Does not occur.** On the wire there is only `Connection: keep-alive`, `Accept`, `Authorization`, `Host`, `User-Agent`. Six requests in a row: 200 six times. No `send_te` needed and none present. |
| `read_response` lost a gzip body | It requests no compression on its own, and authentik does not compress even on `Accept-Encoding: gzip` (`content-encoding: none`). The fix in the sync role still applies here, because the same role is used. |
| LWP follows redirects if you let it | `max_redirects => 0` returns the 302 as a response with `Location`, which is exactly what `read_response` treats as success below 400. Checked at the authorize endpoint. |
| LWP reports "no contact" as 500 with `Client-Warning: Internal response` | The future **fails**, with a list of strings instead of an object: refused connection → `('127.0.0.1:9 - connect: Connection refused failed [Connection refused]')`, timeout → `('Timed out', 'timeout')`. `send_request_f` has to map that to `Net::Async::Authentik::Error::Network`. |

In addition, two things it brings that are new: it **keeps the connection open** and sends three
requests over the same socket (LWP opened a new one each time), and it loads
`IO::Async::Internals::Connector` and, for HTTPS, `IO::Async::SSL` only on the first
connection setup — if a module dies there, with `max_connections_per_host => 1`
the slot stays occupied forever and every further request hangs without an error (see skill
`perl-io-async-future`). Task 2 catches that.

## Global Constraints

- Every public method of the sync dist exists here under the same name plus `_f` and returns a future. Do not invent an API of your own.
- What is not I/O comes from `WWW-Authentik`: `Role::HTTP` (`build_request`, `read_response`, `flatten_field_errors`, `json_codec`), `Diff`, `API->resolvable_fields`. Do not copy.
- `cpanfile`: `requires 'WWW::Authentik', '0.001';`
- One package per file, every file under `lib/` with `# ABSTRACT:` (ASCII only) and `our $VERSION = '0.001';`.
- **Never block the loop.** No `->get` and no `await` on anything synchronous in library code, no synchronous HTTP client.
- An error is **not thrown; the future fails** — also for wrong arguments. The caller never gets an exception from a `*_f`.
- `IO::Async::Notifier->new` passes every key to `configure`, which rejects unknown ones: remove own attributes in `FOREIGNBUILDARGS`.
- Every future someone needs is held until it is done; shared fetches are handed to each caller as `without_cancel`, so that a cancellation does not take the fetch along.
- 2 spaces indentation, `my ( $self, ... ) = @_;`, `is => 'ro'`, `namespace::autoclean`, types from `Types::Standard`.
- Tests run with `PERL5LIB=$HOME/dev/p5-www-authentik/lib prove -lr t`; the live suite only with `AUTHENTIK_LIVE_TEST=1`, `AUTHENTIK_URL` and `AUTHENTIK_TOKEN`.
- Public repo: no hostnames except `127.0.0.1` and `example.org`, no tokens.

## Review Focus

Five things that can only go wrong asynchronously and that no ported suite checks on its own.

1. **Two callers, one fetch.** Twenty concurrent `verify_token_f` may trigger one discovery and one key fetch, not twenty. Test `concurrent callers share the fetch` in `t/70-async.t` (task 5).
2. **One caller cancels, the others do not.** `$first->cancel` on a shared fetch must not cost the second caller its response. Test `cancelling one caller` in `t/70-async.t` (task 5).
3. **An object without a loop.** Every method must return a failed future that says what is missing — no exception and no hang. Test `not in a loop` in `t/70-async.t` (task 5).
4. **A lost future.** An `ensure_*_f` whose return value nobody holds must not leave a half-done change behind; the warning "lost its returning future" must not appear in any test run. Test `nothing is written by a future nobody holds` in `t/70-async.t` (task 5).
5. **Pagination over several pages.** `_paged_f` must follow `pagination.next`, stop at 0 and, on a response whose `next` points back, abort instead of looping forever. Test `pagination` in `t/50-api.t` (task 4) and `_paged_f over three pages` in `t/70-async.t`.

## Files

| File | Responsibility | Task |
|---|---|---|
| `cpanfile` | dependencies, among them `WWW::Authentik` | 1 |
| `lib/Net/Async/Authentik/Error.pm`, `Error/Validation.pm`, `Error/Network.pm`, `Error/API.pm` | errors, each at the same time the sync dist's class | 1 |
| `lib/Net/Async/Authentik/Role/HTTP.pm` | `send_request_f`, `fail_validation`, error classes | 2 |
| `t/lib/FakeAuthentik.pm`, `t/lib/FakeHTTP.pm` | emulated authentik (copy from the sync dist) and a `Net::Async::HTTP` stand-in | 2 |
| `lib/Net/Async/Authentik/OIDC.pm` | OIDC, shared fetches | 3 |
| `lib/Net/Async/Authentik.pm` | facade on `IO::Async::Notifier` | 3 |
| `lib/Net/Async/Authentik/API.pm` | API v3, `_paged_f`, `resolve_f`, `ensure_*_f` | 4 |
| `t/00-load.t`, `t/20-errors.t`, `t/40-facade.t`, `t/50-api.t`, `t/51-api-ensure.t`, `t/52-api-resolve.t`, `t/60-oidc.t` | the ported suites | 2–4 |
| `t/70-async.t` | what only goes wrong asynchronously | 5 |
| `t/lib/AuthentikExecutor.pm`, `t/90-live-authentik.t`, `t/authentik/` | live suite | 6 |
| `README.md`, `Changes`, `CLAUDE.md`, core skill | bring up to date | 6 |

---

### Task 1: Dependencies and the error classes

**Files:** `cpanfile`, `lib/Net/Async/Authentik/Error.pm`, `Error/Validation.pm`, `Error/Network.pm`, `Error/API.pm`, `t/00-load.t`

**Interfaces:**
- Produces: `Net::Async::Authentik::Error` extends `WWW::Authentik::Error`; `::Error::API` extends `WWW::Authentik::Error::API` **and** `Net::Async::Authentik::Error`, likewise `::Validation` and `::Network`. Each is thereby also the sync dist's class, and code that catches `WWW::Authentik::Error::API` catches them too.

- [ ] **Step 1: `cpanfile`**

```perl
requires 'perl', '5.020';
requires 'Crypt::JWT';
requires 'Future';
requires 'Future::AsyncAwait';
requires 'IO::Async';
requires 'IO::Async::SSL';
requires 'JSON::MaybeXS';
requires 'Moo';
requires 'Net::Async::HTTP';
requires 'Type::Tiny';
requires 'URI';
requires 'WWW::Authentik', '0.001';
requires 'namespace::autoclean', '0.16';

on test => sub {
    requires 'CryptX';
    requires 'HTTP::Message';
    requires 'Test::More', '0.96';
};
```

`IO::Async::SSL` is a hard dependency, although `Net::Async::HTTP` only recommends it: without it the first HTTPS request hangs instead of failing (skill `perl-io-async-future`).

Run: `cpanm --installdeps .` — Expected: without errors.

- [ ] **Step 2: Write the four error classes**

Each is four lines of Moo plus POD, following the pattern of `Net::Async::Keycloak::Error`:

```perl
package Net::Async::Authentik::Error::API;

# ABSTRACT: Net::Async::Authentik's API error, a WWW::Authentik::Error::API

use Moo;
extends 'WWW::Authentik::Error::API', 'Net::Async::Authentik::Error';

our $VERSION = '0.001';
```

`Net::Async::Authentik::Error` itself only extends `WWW::Authentik::Error`.

- [ ] **Step 3: `t/00-load.t` and a first run**

List all nine modules (they come into being in the following tasks; until then only the existing ones).
Run: `PERL5LIB=$HOME/dev/p5-www-authentik/lib prove -lr t` — Expected: PASS.
Commit: `Add the dependencies and the error classes`.

---

### Task 2: The HTTP role and the test harness

**Files:** `lib/Net/Async/Authentik/Role/HTTP.pm`, `t/lib/FakeAuthentik.pm`, `t/lib/FakeHTTP.pm`, `t/20-errors.t`

**Interfaces:**
- Consumes: `WWW::Authentik::Role::HTTP`.
- Produces: role with `api_error_class`, `network_error_class`, `validation_error_class`, `fail_validation($message)` → failed future, `send_request_f( $method, $url, %arg )` → future of `{ status, data, location, content }`.
- `FakeHTTP->new( fake => $fake )` with `do_request( request => $request )` → already completed future; `->fake` returns the `FakeAuthentik`.

- [ ] **Step 1: Take over `t/lib/FakeAuthentik.pm`**

Copy of `~/dev/p5-www-authentik/t/lib/FakeAuthentik.pm`, unchanged except for a
header comment that says where it comes from and that both have to stay the same. A
test file cannot be pulled in as a dependency, hence the copy — as with
`Net::Async::Keycloak`. In addition, a check in `t/00-load.t` that compares the two files
when the sync dist is checked out next to it, and is skipped otherwise:

```perl
my $sync = $ENV{WWW_AUTHENTIK_DIR} || "$ENV{HOME}/dev/p5-www-authentik";
SKIP: {
  skip 'the sync distribution is not checked out next door', 1 unless -f "$sync/t/lib/FakeAuthentik.pm";
  my $here  = do { local ( @ARGV, $/ ) = 't/lib/FakeAuthentik.pm'; <> };
  my $there = do { local ( @ARGV, $/ ) = "$sync/t/lib/FakeAuthentik.pm"; <> };
  # the header comment differs on purpose; everything from `use strict` on must not
  is( ( $here =~ s/\A.*?^use strict;/use strict;/smr ), ( $there =~ s/\A.*?^use strict;/use strict;/smr ),
    'the fake authentik has not drifted from the sync distribution' );
}
```

- [ ] **Step 2: Write `t/lib/FakeHTTP.pm`**

```perl
package FakeHTTP;

# What Net::Async::Authentik needs from Net::Async::HTTP, answered by the
# in-memory authentik of t/lib/FakeAuthentik.pm as already completed futures.
# No loop is needed.

use strict;
use warnings;
use Future;
use FakeAuthentik;

sub new {
  my ( $class, %arg ) = @_;
  return bless { fake => $arg{fake} || FakeAuthentik->new(%arg) }, $class;
}

sub fake { $_[0]{fake} }

sub do_request {
  my ( $self, %arg ) = @_;
  return Future->done( $self->{fake}->request( $arg{request} ) );
}

1;
```

- [ ] **Step 3: Write `lib/Net/Async/Authentik/Role/HTTP.pm`**

```perl
package Net::Async::Authentik::Role::HTTP;

# ABSTRACT: Sending requests to authentik through Net::Async::HTTP

use Future;
use Net::Async::Authentik::Error::API;
use Net::Async::Authentik::Error::Network;
use Net::Async::Authentik::Error::Validation;
use Scalar::Util qw( blessed );
use Moo::Role;

our $VERSION = '0.001';

sub api_error_class        { 'Net::Async::Authentik::Error::API' }
sub network_error_class    { 'Net::Async::Authentik::Error::Network' }
sub validation_error_class { 'Net::Async::Authentik::Error::Validation' }

sub fail_validation {
  my ( $self, $message ) = @_;
  return Future->fail( $self->validation_error_class->new( message => $message ) );
}

sub send_request_f {
  my ( $self, $method, $url, %arg ) = @_;
  my $request = $self->build_request( $method, $url, %arg );
  # Net::Async::HTTP dies instead of failing when it is in no loop
  my $sent = eval { $self->http->do_request( request => $request ) };
  return Future->fail( $self->network_error_class->new( message => $method.' '.$url.': could not send ('
    .( $@ =~ s/ at \S+ line \d+.*//sr ).'); was the Net::Async::Authentik added to a loop?' ) ) unless $sent;
  return $sent->else( sub {
    my ( $message ) = @_;
    return Future->fail($message) if blessed $message;
    # a refused connection or a timeout arrives as plain strings
    return Future->fail( $self->network_error_class->new( message => $method.' '.$url.': '.$message ) );
  } )->then( sub {
    my ( $response ) = @_;
    my $result = eval { $self->read_response( $response, $method, $url, %arg ) };
    return $result ? Future->done($result) : Future->fail($@);
  } );
}

1;
```

The role is composed **before** `WWW::Authentik::Role::HTTP`, so that its
error class methods win:

```perl
with 'Net::Async::Authentik::Role::HTTP';
with 'WWW::Authentik::Role::HTTP';
```

POD: `=description` says that requests and responses are built and read by the sync role,
so that both clients map authentik's responses the same way, and that this
role only sends.

- [ ] **Step 4: Port `t/20-errors.t`**

The sync dist's suite, every call as `->get`, and instead of `error_of { ... }` a
helper that takes the failure of the future:

```perl
sub failure_of { my ( $future ) = @_; $future->is_failed ? ( $future->failure )[0] : undef }
```

In addition three checks that only exist here: every error class is also the sync dist's
(`isa_ok( $error, 'WWW::Authentik::Error::API' )`), a wrong argument **fails the
future instead of throwing**, and a refused connection becomes
`Net::Async::Authentik::Error::Network`.

Run: `PERL5LIB=… prove -lr t` — Expected: PASS.
Commit: `Add the HTTP role and the test harness`.

---

### Task 3: OIDC and the facade

**Files:** `lib/Net/Async/Authentik/OIDC.pm`, `lib/Net/Async/Authentik.pm`, `t/40-facade.t`, `t/60-oidc.t`

**Interfaces:**
- Produces: `Net::Async::Authentik->new( base_url =>, application =>, client_id =>, token =>, http => )` with `->oidc`, `->api`, `->issuer`, `->application_url`, `->api_url`, `->for_application($slug)`, `->http`.
- `Net::Async::Authentik::OIDC->new( application_url =>, http =>, client_id =>, algorithms =>, jwks_min_age =>, now => )` with `discovery_f`, `jwks_f`, `endpoint_f`, `issuer_f`, the eight `*_endpoint_f`, `issuer_names_the_application_f`, `verify_token_f`, `userinfo_f`, `introspect_f`, `revoke_f`, `client_credentials_token_f`, `refresh_token_f`, `exchange_authorization_code_f`, `device_authorization_f`, `device_token_f`, `authorization_url_f`.

- [ ] **Step 1: Write the tests**

`t/40-facade.t` as in the sync dist, plus: `http` is a child node of the facade
(`grep { $_ == $ak->http } $ak->children`), an `http` passed in is **not** added as a child,
`for_application` shares it, and the facade also accepts a hash reference.
The sync checks for `max_redirect` and `send_te` are dropped; instead:
`max_redirects` is 0 and `fail_on_error` is false, so that a 404 comes back as a response
and `read_response` turns it into an error.

`t/60-oidc.t` as in the sync dist, every call `->get`, including the subtest
`two applications of one instance` with `issuer_mode: global`.

- [ ] **Step 2: Write `lib/Net/Async/Authentik/OIDC.pm`**

Attributes like the sync class, but `http` instead of `ua`, and the state as `rw`:
`_discovery`, `_jwks`, `_jwks_fetched`, `_in_flight` (`default => sub { {} }`).

The shared fetch, literally as in the Keycloak twin:

```perl
# One fetch for everybody who asks while it is under way, each with a view of
# its own so that cancelling one does not cancel the fetch.
sub _shared {
  my ( $self, $key, $start ) = @_;
  my $in_flight = $self->_in_flight;
  unless ( $in_flight->{$key} ) {
    my $future = $start->()->on_ready( sub { delete $in_flight->{$key} } );
    return $future if $future->is_ready;
    $in_flight->{$key} = $future;
  }
  return $in_flight->{$key}->without_cancel;
}
```

`discovery_f` and `jwks_f` go through it; `jwks_f` sets `_jwks_fetched` **at the start**,
so that checks already running see it.

`verify_token_f` is the sync method with `await` in front, with all three points from
spec 13.2: `client_id` as the preset `audience`, the refusal to verify without
a distinguishing issuer (`any_audience => 1` lifts it), and the
`scope` heuristic for `type`. The difference from the sync version: the issuer comes from
a future, so

```perl
async sub issuer_names_the_application_f {
  my ( $self ) = @_;
  return ( await $self->issuer_f ) eq $self->application_url.'/' ? 1 : 0;
}
```

and `verify_token_f` waits for `issuer_f` and `issuer_names_the_application_f` before it
decides. Reloading the keys may also happen while a fetch is currently
running (`$self->_in_flight->{jwks} || $self->now->() - ... >= $self->jwks_min_age`), otherwise
twenty concurrent checks with a rotated key fail.

`authorization_url_f` is the only thing that would need no I/O — but it needs the
endpoint from the discovery, so it is a future as well.

- [ ] **Step 3: Write `lib/Net/Async/Authentik.pm`**

```perl
use Moo;
extends 'IO::Async::Notifier';

sub FOREIGNBUILDARGS {
  my ( $class, @args ) = @_;
  my %arg = @args == 1 && ref $args[0] eq 'HASH' ? %{ $args[0] } : @args;
  delete @arg{qw( base_url application client_id token http )};
  return %arg;
}

sub BUILDARGS {
  my ( $class, @args ) = @_;
  my %args = @args == 1 && ref $args[0] eq 'HASH' ? %{ $args[0] } : @args;
  $args{base_url} =~ s{/+\z}{} if defined $args{base_url};
  return \%args;
}
```

`http` is `is => 'lazy'` and is added as a child:

```perl
sub _build_http {
  my ( $self ) = @_;
  # no redirects: authentik answers 302 wherever it wants a browser, and
  # those answers are read, not followed. fail_on_error off, so that a 4xx
  # comes back as a response and read_response can turn it into an error.
  my $http = Net::Async::HTTP->new(
    user_agent     => 'Net-Async-Authentik/'.$VERSION,
    max_redirects  => 0,
    fail_on_error  => 0,
    timeout        => 30
  );
  $self->add_child($http);
  return $http;
}
```

`oidc` and `api` as in the sync facade, but they do not fail on construction: a
missing slug or a missing token only becomes a **failed
future** on the call, because an attribute access should not throw. So `_build_oidc` and
`_build_api` always build the sub-object, and the methods there check.

The facade's POD names, like the sync dist's, the difference in the return value
(`{ object, changed }`) and in addition: first `$loop->add($ak)`, otherwise every request fails
with a network error that says exactly that.

- [ ] **Step 4: Run the tests, commit**

Run: `PERL5LIB=… prove -lr t` — Expected: PASS.
Commit: `Add the OIDC client and the facade`.

---

### Task 4: `Net::Async::Authentik::API`

**Files:** `lib/Net/Async/Authentik/API.pm`, `t/50-api.t`, `t/51-api-ensure.t`, `t/52-api-resolve.t`

**Interfaces:**
- Consumes: `WWW::Authentik::Diff`, `WWW::Authentik::API->resolvable_fields`.
- Produces: every method of `WWW::Authentik::API` with `_f`, plus `call_f`, `_paged_f`, `resolve_f`, `_ensure_f`.

- [ ] **Step 1: Port the three suites**

Literally those of the sync dist, with `_f` and `->get`. In `t/50-api.t` the pagination is added,
which here is a loop with `await` instead of a `while` loop.

- [ ] **Step 2: Transport, pagination, resolution**

```perl
async sub call_f {
  my ( $self, $method, $path, $body ) = @_;
  $path = '/'.$path unless $path =~ m{\A/};
  my %arg = defined $body ? ( json => $body ) : ();
  return await $self->send_request_f( $method, $self->api_url.$path, %arg, bearer => $self->token );
}

async sub _paged_f {
  my ( $self, $path, %query ) = @_;
  my $page_size = delete $query{page_size} // $self->page_size;
  my ( @all, %seen );
  my $page = 1;
  while ( defined $page && $page > 0 && !$seen{$page}++ ) {
    my $data = await $self->_data_f( GET => $path.$self->_query( %query, page => $page, page_size => $page_size ) );
    last unless ref $data eq 'HASH';
    push @all, @{ $data->{results} || [] };
    $page = ref $data->{pagination} eq 'HASH' ? $data->{pagination}{next} : 0;
  }
  return \@all;
}
```

`_query` and `_esc` are pure functions and are inherited from `WWW::Authentik::API` —
no: the sync class is not a role. They are written here as the same three lines,
and `resolvable_fields` is **delegated**, so that the table exists
only once:

```perl
sub resolvable_fields { WWW::Authentik::API->resolvable_fields }

async sub resolve_f {
  my ( $self, $rep ) = @_;
  my %out    = %$rep;
  my $fields = $self->resolvable_fields;
  ...   # the same order and the same checks as in the sync dist,
        # but `my $found = await $self->${\ ( $spec->{find}.'_f' ) }($value);`
  return \%out;
}
```

The name of the lookup method is the sync dist's plus `_f`. That the table is shared
keeps the rule from spec 12 (no guessing detection) the same in both dists.

- [ ] **Step 3: The basic operations and `ensure_*_f`**

Each method one line following the pattern of the sync dist. `_ensure_f`:

```perl
async sub _ensure_f {
  my ( $self, %arg ) = @_;
  my $current = await $arg{find}->();
  unless ($current) {
    my $object = await $arg{create}->();
    await $arg{after_create}->($object) if $arg{after_create};
    return { object => $object, changed => 'created' };
  }
  my $changes = $self->diff_class->changes( $current, $arg{wanted} );
  return { object => $current, changed => '' } unless %$changes;
  return { object => await $arg{update}->( $current, $changes ), changed => 'updated' };
}
```

`diff_class` is `WWW::Authentik::Diff`, so the same comparison, including the
rule from spec 13.2 about trimmed text fields.

Every check that throws in the sync dist returns a failed future here:
`return $self->fail_validation('ensure_user needs a username') unless defined $rep{username};`

- [ ] **Step 4: Run the tests, commit**

Commit: `Add the API v3 client with the ensure methods`.

---

### Task 5: `t/70-async.t`

**Files:** `t/70-async.t`

A `DeferredHTTP` whose responses only come when the test says so, as in the
Keycloak twin. Subtests:

- `concurrent callers share the fetch` — twenty `verify_token_f` with an unknown `kid`: one discovery, two key fetches (the first one and one because of the unknown keys), twenty failed futures with a validation error.
- `cancelling one caller leaves the fetch alone` — two callers share a fetch, the first cancels, the second gets its response.
- `requests run side by side` — three `*_f` at the same time, three requests in flight, all three done.
- `_paged_f over three pages` — 25 objects at `page_size => 10`: three requests, 25 matches; a response whose `next` points back aborts.
- `not in a loop` — every method returns a failed future with `Net::Async::Authentik::Error::Network`, whose message contains "added to a loop".
- `wrong arguments fail the future` — `ensure_user_f()`, `find_user_f(undef)`, `resolve_f({ scopes => undef })`: failed, not thrown, and each time a validation error.
- `nothing is written by a future nobody holds` — an `ensure_group_f` whose return value is dropped, followed by a held run: the counter `$fake->writes` may rise at most once, and `$SIG{__WARN__}` must not see "lost its returning future".

Commit: `Add the asynchronous behaviour tests`.

---

### Task 6: Live suite and bring up to date

**Files:** `t/lib/AuthentikExecutor.pm`, `t/90-live-authentik.t`, `t/authentik/docker-compose.yml`, `t/authentik/env.example`, `t/authentik/ci-live-job.yml`, `README.md`, `Changes`, `CLAUDE.md`, `.claude/skills/net-async-authentik-core/SKILL.md`, `t/00-load.t`

- [ ] **Step 1: Port the live suite**

The sync dist's with `_f` and `->get`, own prefix `naauth-live-…`, the same
`END` block, including the service account of the client credentials grant. The
executor helper comes along as a copy (it speaks HTTP by itself and stays
synchronous; that is test code, not library code).

In addition two checks that only exist here: the facade is added to the loop, and a
`Future->needs_all` over three `ensure_*_f` runs in parallel against the real authentik and
all three report nothing on the second run.

- [ ] **Step 2: Take over the compose file and the CI job**

`t/authentik/docker-compose.yml` and `env.example` as in the sync dist. The live job
goes into the repo as `t/authentik/ci-live-job.yml`, not into `.github/workflows/`: the
deploy key may not push workflow files.

- [ ] **Step 3: `README.md`, `Changes`, `CLAUDE.md`, Core-Skill, `t/00-load.t`**

No "Skeleton state" any more; the README shows `$loop->add($ak)` and one example each for
`oidc` and `api`.

- [ ] **Step 4: Run everything**

Run: `PERL5LIB=$HOME/dev/p5-www-authentik/lib prove -lr t && PERL5LIB=… dzil test --all`
and the live suite against the throwaway instance. Expected: all PASS.
Commit: `Add the live suite and bring the docs to the built state`.

---

## Self-check against the spec

- **Section 9 (twin)** → `build_request`/`read_response` and `Diff` from the sync dist (tasks 2 and 4), `_paged_f` and `resolve_f` as methods of their own with the same table (task 4).
- **Sections 5 and 6** → every method with `_f` (tasks 3 and 4).
- **Section 7** → the error hierarchy, each class at the same time the sync dist's (task 1).
- **Section 13.1** → the four hazards above re-checked; `TE` is dropped, the rest holds.
- **Section 13.2** → `verify_token_f` with `client_id`, audience requirement and `any_audience`; `resolve_f` with the same refusals; `find_*_f(undef)` fails; the comparison is the same.

## Clarified after the build (2026-10-04)

An independent review without build context, with probes against the running authentik 2026.8.3,
found six points. Five are fixed and pinned by tests; the sixth is
a bug in Future::AsyncAwait that this dist cannot fix.

### The crash at program exit — Future::AsyncAwait 0.71, not this dist

The review reported a reproducible crash of the interpreter (`double free or
corruption`, `free(): invalid pointer`, segmentation fault) when cancelling running
futures. The re-check confirmed it and then classified it differently than reported:

- **It has nothing to do with cancelling.** The same call without `cancel` crashes just the same.
- **The trigger is a reference in the frame of an `async sub` that is still suspended
  at program exit.** With a string instead of the reference the same flow is clean.
- **It happens in the global destruction phase**, after the program's work: the output
  still appears, the exit status is 134 or 139.
- **Neither `Net::Async::HTTP` nor `IO::Async` nor Moo are involved.** Eight lines of plain
  Future::AsyncAwait are enough; they are in the repo as `docs/future-asyncawait-0.71-crash.pl`,
  together with what changes something about it and what does not.
- **The caller cannot protect against it** by holding the future or
  calling `->retain` — only by letting it finish.

0.71 is the latest version on CPAN, so pinning does not help. What the dist does:
`pairs_or_fail` in `Net::Async::Authentik::Role::HTTP` checks, in every `async sub` that
collects a hash list, the shape of the argument list beforehand and fails the future on an
odd one — that was the easiest way to accidentally get a reference into such a
frame. And the facade's POD and the README now say explicitly that every future
has to finish before program exit, with the reference to the reproducer. Preparing it for PEVANS
and reporting it: Getty's decision, not mine.

### Fixed

- **`send_request_f` could throw.** `build_request` stood outside the `eval`, and a
  body the JSON encoder cannot handle made `call_f` throw an exception instead of failing the
  future — against the promised rule that nothing throws here. Now a
  validation error in the future.
- **`ensure_binding_f` reported every error as "no flow".** An `eval` around the lookup also caught
  a refused connection, a 401 and a 500 and turned them into the claim
  that the flow did not exist. Now only a missing match becomes a validation error,
  everything else stays what it is.
- **`uuid_pattern` and `integer_pattern` were missing.** The sync dist has had them since `45325ea` as
  public class methods; the twin used them but did not expose them. Now
  it delegates them, and a test compares both classes method by method in both
  directions.
- **`_detail_f` could die with the empty string.** It told success and
  failure apart by the truth of the result; a response without a body led to `die ''`. Now
  what decides is whether `eval` failed.
- **`_fetch_jwks_f` did not check what came back.** A body that is not a JSON object left
  the cache empty, and every check fetched the keys again. Now the same
  check as for the discovery document three lines above.

### Checked and found in order

The shared fetch when the first one **fails** (twice in a row, no getting stuck);
all callers cancel (the next one gets a fresh view); the mapping of all six
error forms of `Net::Async::HTTP` (DNS, refused, timeout, broken status line,
connection drop in the body, drop before the header) to `Error::Network`, each as an object;
"nothing throws" over about 70 methods times six argument shapes; the lifetime (after
`$loop->remove` the object is freed, no `$self` held on to); `for_application`;
and `ensure_*` against the real authentik through **both** clients one after the other, which agree
on what a change is.

### Not reached by the review

A real OIDC run against the instance, the live suite and `dzil build`. All three
ran here: `prove -lr t`, `dzil test --all` and `t/90-live-authentik.t` twice
in a row.
