#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeAuthentik;
use FakeHTTP;
use Net::Async::Authentik;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }
sub text_of { defined $_[0] ? "$_[0]" : '' }

my $fake = FakeAuthentik->new;
my $provider = $fake->add( providers => {
  name => 'probe-provider', client_id => 'probe-client', client_secret => 'probe-secret',
  authorization_flow => 'f', invalidation_flow => 'f', redirect_uris => [],
  grant_types => [qw( client_credentials refresh_token authorization_code )]
} );
$fake->add( applications => { name => 'Probe App', slug => 'probe-app', provider => $provider->{pk} } );
my $oidc = Net::Async::Authentik::OIDC->new(
  application_url => $fake->base.'/application/o/probe-app',
  http            => FakeHTTP->new( fake => $fake ),
);

subtest 'the JWKS answer carries no keys' => sub {
  # a proxy, or a jwks_uri that points somewhere else, answers with
  # something else. Such an answer must not be cached: every token would
  # fail later with a key lookup error
  $fake->answer( qr{/application/o/probe-app/jwks/\z}, 200, { detail => 'no keys here' } );

  my $error = error_of { $oidc->jwks_f->get };
  isa_ok( $error, 'Net::Async::Authentik::Error::API', 'a JWKS answer without keys is an error' );
  is( $error ? $error->http_status : undef, 200, 'the status is carried' );
  like( text_of($error), qr/\AGET /, 'the message names the method' );
  like( text_of($error), qr{\Q/application/o/probe-app/jwks/\E}, 'and the path' );
  like( text_of($error), qr/keys/, 'and says that the keys are missing' );
};

subtest 'the token is not to blame' => sub {
  # the answer of the JWKS is the problem, not the token: the error says so
  $fake->answer( qr{/application/o/probe-app/jwks/\z}, 200, { detail => 'no keys here' } );
  my $jwt = $fake->sign( $fake->claims_for( slug => 'probe-app', aud => 'probe-client' ) );

  my $error = error_of { $oidc->verify_token_f($jwt)->get };
  isa_ok( $error, 'Net::Async::Authentik::Error::API', 'the answer of the JWKS is the error' );
  unlike( text_of($error), qr/token rejected/, 'and not the token' );
};

done_testing;
