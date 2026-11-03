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
  grant_types => [qw( client_credentials refresh_token authorization_code urn:ietf:params:oauth:grant-type:device_code )]
} );
$fake->add( applications => { name => 'Probe App', slug => 'probe-app', provider => $provider->{pk} } );
my $oidc = Net::Async::Authentik::OIDC->new(
  application_url => $fake->base.'/application/o/probe-app',
  http            => FakeHTTP->new( fake => $fake ),
);
my %client = ( client_id => 'probe-client', client_secret => 'probe-secret' );

subtest 'the token endpoint redirects' => sub {
  # a proxy in front of authentik, or a base_url that points at the wrong
  # scheme: the user agent follows no redirect, and no token comes back
  $fake->answer( qr{/application/o/token/\z}, 302, '', 'Location' => 'https://id.example.org/application/o/token/' );

  my $error = error_of { $oidc->client_credentials_token_f(%client)->get };
  isa_ok( $error, 'Net::Async::Authentik::Error::API', 'a redirect at the token endpoint is an error' );
  isa_ok( $error, 'WWW::Authentik::Error::API', 'and the sync class as well' );
  is( $error ? $error->http_status : undef, 302, 'the status is carried' );
  like( text_of($error), qr/was redirected/, 'the message says so' );
  like( text_of($error), qr/302/, 'and names the status' );
  like( text_of($error), qr{\Qapplication/o/token/\E}, 'and the endpoint' );
  unlike( text_of($error), qr/probe-secret/, 'and never the secret' );
};

subtest 'the token endpoint answers without a token' => sub {
  # a 2xx that carries no access_token: the caller would send an empty
  # Bearer and find out much later
  $fake->answer( qr{/application/o/token/\z}, 200, { token_type => 'Bearer' } );

  my %grant = (
    client_credentials_token    => sub { $oidc->client_credentials_token_f(%client) },
    refresh_token               => sub { $oidc->refresh_token_f( 'a-refresh-token', %client ) },
    exchange_authorization_code => sub { $oidc->exchange_authorization_code_f( code => 'a-code',
      redirect_uri => 'https://app.example.org/cb', %client ) },
    device_token                => sub { $oidc->device_token_f( device_code => 'a-device-code', %client ) },
  );
  for my $what ( sort keys %grant ) {
    my $error = error_of { $grant{$what}->()->get };
    isa_ok( $error, 'Net::Async::Authentik::Error::API', $what );
    like( text_of($error), qr/access_token/, "$what: says what is missing" );
    like( text_of($error), qr{\Qapplication/o/token/\E}, "$what: and names the endpoint" );
    unlike( text_of($error), qr/probe-secret/, "$what: and never the secret" );
  }
};

subtest 'the endpoints that carry no token' => sub {
  # introspect answers { active => ... }, revoke nothing and the device
  # endpoint a device_code: none of them carries an access_token, and none
  # of them is an error
  my $state = $oidc->introspect_f( 'a-token', %client )->get;
  ok( exists $state->{active}, 'introspect answers without an access_token' );
  ok( $oidc->revoke_f( 'a-token', %client )->get, 'revoke answers without one' );
  my $start = $oidc->device_authorization_f(%client)->get;
  ok( $start->{device_code}, 'the device endpoint answers without one' );
};

done_testing;
