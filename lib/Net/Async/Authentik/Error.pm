package Net::Async::Authentik::Error;

# ABSTRACT: Exception base class for Net::Async::Authentik

use Moo;
extends 'WWW::Authentik::Error';

our $VERSION = '0.002';

=synopsis

    $ak->api->get_user_f($pk)->else( sub {
      my ( $error ) = @_;
      return Future->done(undef) if $error->isa('Net::Async::Authentik::Error::API') && $error->is_not_found;
      return Future->fail($error);
    } );

=description

A failed future of Net::Async::Authentik fails with one of
L<Net::Async::Authentik::Error::Validation>,
L<Net::Async::Authentik::Error::Network> and
L<Net::Async::Authentik::Error::API>. Nothing is thrown: a wrong argument
fails the future just as a refused request does, so one C<else> catches both.

Each of them is also the matching L<WWW::Authentik::Error> class, so code
written against the synchronous client catches them unchanged, and each
stringifies to its message.

=cut

1;
