# -*- perl -*-
package Utils;

use strict;
use warnings;
use Carp;
sub r_conf_interval {
  my $class = shift;
  my %args = @_;
  my $r = $args{r};
  my $n = $args{n};
  croak "n must be > 3 or interval not calculable"
    unless $n > 3;
  croak "r must be -1 < r < 1"
    unless abs($r) < 1;

  # Basically, a random r value does not have a uniform distribution,
  # but the z transformation does (and has a closed form for the
  # standard deviation of n**-0.5). So we convert to z, calculate the
  # interval, and then convert back.

  use Math::Trig;
  # http://en.wikipedia.org/wiki/Fisher_transformation
  # http://onlinestatbook.com/chapter8/correlation_ci.html

  # converting to z space
  my $z = atanh($r);
  my $sigma = 1 / sqrt( $n - 3 );

  # 95% confidence interval
  my $delta_z = 1.96 * $sigma;

  # convert back
  my $low_r  = tanh( $z - $delta_z );
  my $high_r = tanh( $z + $delta_z );
  return ($low_r, $high_r);
}
1;
