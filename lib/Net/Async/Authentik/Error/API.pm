package Net::Async::Authentik::Error::API;

# ABSTRACT: API

use Moo;
extends 'WWW::Authentik::Error::API', 'Net::Async::Authentik::Error';

our $VERSION = '0.002';

=description

The same error as L<WWW::Authentik::Error::API>, with the same attributes
and methods. It is both a L<WWW::Authentik::Error::API> and a
L<Net::Async::Authentik::Error>.

=cut

1;
