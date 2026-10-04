package Net::Async::Authentik::Error::Validation;

# ABSTRACT: Raised for wrong arguments, missing credentials and rejected tokens

use Moo;
extends 'WWW::Authentik::Error::Validation', 'Net::Async::Authentik::Error';

our $VERSION = '0.001';

=description

The same error as L<WWW::Authentik::Error::Validation>, with the same attributes
and methods. It is both a L<WWW::Authentik::Error::Validation> and a
L<Net::Async::Authentik::Error>.

=cut

1;
