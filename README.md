# Net-Async-Authentik

Async Perl client for the [authentik](https://goauthentik.io/) identity provider, on
[IO::Async](https://metacpan.org/pod/IO::Async) and
[Future](https://metacpan.org/pod/Future): the twin of
[`WWW::Authentik`](https://github.com/Getty/p5-www-authentik), same API with `_f` suffixes.

Developed and live-tested against authentik 2026.8.3.

## Synopsis

```perl
use Future::AsyncAwait;
use IO::Async::Loop;
use Net::Async::Authentik;

my $loop = IO::Async::Loop->new;
my $ak   = Net::Async::Authentik->new(
  base_url    => 'https://id.example.org',
  application => 'my-app',                   # the application slug, for OIDC
  client_id   => $client_id,                 # its provider's client id, checked as the audience
  token       => $ENV{AUTHENTIK_TOKEN},      # an API token, for the REST API
);
$loop->add($ak);                             # nothing works before this
```

### OpenID Connect

```perl
my $oidc   = $ak->oidc;
my $tokens = await $oidc->client_credentials_token_f( client_id => $id, client_secret => $secret, scope => 'openid' );
my $claims = await $oidc->verify_token_f( $tokens->{access_token}, type => 'access' );
```

Callers asking for the discovery document or the signing keys while a fetch is under way
share that one fetch, and each gets a view that can be cancelled without taking the fetch
down with it.

### The REST API

```perl
my $api  = $ak->api;
my $user = await $api->find_user_f('alice');
await $api->set_password_f( $user->{pk}, $password );

# three at once
my @groups = await Future->needs_all( map { $api->ensure_group_f( name => $_ ) } qw( a b c ) );
```

### A setup that can run twice

```perl
my $r = await $api->ensure_oauth2_provider_f(
  name                    => 'my-app',
  authorization_flow_slug => 'default-provider-authorization-implicit-consent',
  invalidation_flow_slug  => 'default-provider-invalidation-flow',
  grant_types             => [qw( authorization_code refresh_token )],
  redirect_uris           => [ { matching_mode => 'strict', url => 'https://app.example.org/cb' } ],
  scopes                  => [qw( openid email profile )],
);
print $r->{changed};        # 'created', 'updated' or '' on a run that changed nothing
```

The comparison behind `ensure_*_f`, the resolution of names into identifiers, and the
reading of authentik's answers all come from `WWW::Authentik`, so the two clients cannot
drift apart.

## Two things to know

**Hold the future you get back, and let it finish.** Dropping it does not undo anything:
the work runs to the end, authentik is written to, and the answer goes nowhere. And a
future still pending when the process exits can take the interpreter down in global
destruction — a defect in Future::AsyncAwait 0.71, not in this distribution;
`docs/future-asyncawait-0.71-crash.pl` reproduces it in eight lines without it. Run the
loop until your futures are ready.

**Nothing throws.** A wrong argument fails the future, just as a refused request does, so
one `else` catches both. Every error is also the matching `WWW::Authentik::Error` class.

## Live tests

```bash
PERL5LIB=../p5-www-authentik/lib AUTHENTIK_LIVE_TEST=1 \
  AUTHENTIK_URL=http://127.0.0.1:9000 AUTHENTIK_TOKEN=... prove -lv t/90-live-authentik.t
```

Everything the suite makes carries a random prefix and is deleted again. A throwaway
authentik for it: `t/authentik/docker-compose.yml`, with `t/authentik/env.example` for the
secrets. That compose file raises
`AUTHENTIK_THROTTLE__PROVIDERS__OAUTH2__DEVICE`: authentik throttles the device
authorization endpoint itself to 20 requests an hour per client IP and answers 429
`slow_down` above that, which a handful of runs reach. Against an instance that does not
raise it, the suite bails out saying so.

## License

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.
