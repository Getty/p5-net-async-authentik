#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  Net::Async::Authentik
)) {
  use_ok($_);
}

done_testing;
