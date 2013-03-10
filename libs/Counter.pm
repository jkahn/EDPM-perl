package Counter;

# base class for objects that extract item-counts from sentences.

use strict;
use warnings;
use Carp;

# objects should be singletons given parameter sets

sub count {
  my $self = shift;
  my $sentence = shift;
  my $class = ref $self;
  croak "class $class failed to implement count() method";
}

sub new {
  my $class = shift;

  my $self = bless {}, $class;

  $self->init(@_);
  return $self;
}

sub init {
  my $self = shift;
  my %args = @_;
  $self->{$_} = $args{$_} for keys %args;
}

package Counter::NGram;
use strict;
use warnings;
use Carp;
our @ISA = 'Counter';

sub init {
  my $self = shift;
  $self->SUPER::init(@_);
  croak "no length defined to ", ref $self, " instance "
    unless defined $self->{length};
  croak "length <= 1!"
    unless $self->{length} > 1;
  croak "length non-integer"
    unless $self->{length} == int($self->{length});

}

sub count {
  my $self = shift;
  my $string = shift;
  my @words = split " ", $string;

  
}

1;
