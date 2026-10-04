package Net::Async::Authentik::Error::Network;

# ABSTRACT: Raised when no HTTP answer came back from authentik

use Moo;
extends 'WWW::Authentik::Error::Network', 'Net::Async::Authentik::Error';

our $VERSION = '0.002';

=description

The same error as L<WWW::Authentik::Error::Network>, with the same attributes
and methods. It is both a L<WWW::Authentik::Error::Network> and a
L<Net::Async::Authentik::Error>.

=cut

1;
