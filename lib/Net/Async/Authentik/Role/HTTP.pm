package Net::Async::Authentik::Role::HTTP;

# ABSTRACT: Sending requests to authentik through Net::Async::HTTP

use Future;
use Net::Async::Authentik::Error::API;
use Net::Async::Authentik::Error::Network;
use Net::Async::Authentik::Error::Validation;
use Scalar::Util qw( blessed );
use Moo::Role;

our $VERSION = '0.001';

=description

The asynchronous counterpart of L<WWW::Authentik::Role::HTTP>. Requests are
built and responses read by that role's C<build_request> and
C<read_response>, so both clients map authentik's answers the same way; this
role only sends, through L<Net::Async::HTTP>, and returns futures.

Consume it before L<WWW::Authentik::Role::HTTP>: its error class methods then
win and the errors are this distribution's subclasses.

    with 'Net::Async::Authentik::Role::HTTP';
    with 'WWW::Authentik::Role::HTTP';

The consuming class has an C<http> attribute holding a L<Net::Async::HTTP>.

=cut

sub api_error_class        { 'Net::Async::Authentik::Error::API' }
sub network_error_class    { 'Net::Async::Authentik::Error::Network' }
sub validation_error_class { 'Net::Async::Authentik::Error::Validation' }

=method api_error_class

=method network_error_class

=method validation_error_class

The classes a failed future fails with. They override the synchronous role's,
which is why this role is composed first.

=cut

sub fail_validation {
  my ( $self, $message ) = @_;
  return Future->fail( $self->validation_error_class->new( message => $message ) );
}

=method fail_validation

    return $self->fail_validation('a client_id is needed');

A failed future with a validation error. Nothing in this distribution throws:
a wrong argument fails the future the caller is already holding.

=cut

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
    # a refused connection arrives as one string, a timeout as ('Timed out',
    # 'timeout'); neither is an object the way LWP's internal response was
    return Future->fail( $self->network_error_class->new( message => $method.' '.$url.': '.$message ) );
  } )->then( sub {
    my ( $response ) = @_;
    my $result = eval { $self->read_response( $response, $method, $url, %arg ) };
    return $result ? Future->done($result) : Future->fail($@);
  } );
}

=method send_request_f

    $self->send_request_f( POST => $url, json => \%body, bearer => $token )->then( sub {
      my ( $result ) = @_;   # status, data, location, content
      ...
    } );

Sends one request. Fails with L<Net::Async::Authentik::Error::Network> when
no answer came back and with L<Net::Async::Authentik::Error::API> for any
status of 400 and above. Anything below 400 is an answer, including the 302
authentik gives where it wants a browser.

=cut

1;
