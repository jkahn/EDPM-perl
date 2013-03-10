package Sentence;

# Sentence  root class
#   Sentence::Composite  isa Sentence
#     Sentence::Union          isa Sentence::Composite
#     Sentence::Intersection   isa Sentence::Composite
#     Sentence::Match          isa Sentence::Composite

# Sentence hasa list of counter objects

# Counter objects are initialized at Sentence->new()
#   e.g.
#     [ { class => Counter::NGram,
#         param => [ length => 1 ],
#         weight => 1,
#       },
#       { class => Counter::NGram,
#         param => [ length => 2 ],
#         weight => 1,
#       },
#     ]

# Counter objects are singletons (i.e. generated only once per process)?

use strict;
use warnings;
use Carp;

use constant PARANOID => 1;
# class represents a single hypothesis or reference, possibly with
# weighted counts of components

sub set_counters {
  # sets default counter objects to be used by Sentence class to
  # construct new Sentence objects from Sentence strings
  my $class = shift;

  my @args = @_;

  croak "implement";
}

sub count_items {
  my $self = shift;
  my $string = shift;
  my %census;
  for my $counter ($self->counters) {
    my $cid = $counter->id();
    my %count = $counter->count($string);
    for my $found (keys %count) {
      $key = "$cid $found";
      carp "double-discovery of $key" if defined $census{$key};
      $census{$key} = $count{$found};
    }
  }
  return %census;
}


sub new {
  my $class = shift;
  my %args = @_;
  my $self = bless \%args, $class;
  return $self;
}

sub new_from_string {
  # given string, return new object
  my $class = shift;
  my $string = shift;

  my %item_counts = $class->count_items($string);

  if (PARANOID) {
    for (keys %item_counts) {
      carp "count of item '$_' was $item_counts{$_} and that's <= 0"
	if $item_counts{$_} <= 0;
    }
  }

  my $self = bless { elements => {%item_counts} }, $class;

  return $self;
}

sub length {
  # returns length of object, regardless of how internal counts are stored
  my $self = shift;
  my $sum = 0;
  for my $item ($self->elements()) {
    $sum += $self->element_weight($item);
  }
  return $sum;
}

sub min_diff_length {
  # return length of self that has min diff WRT other

  # effectively dummy method here; Composite object behaves
  # differently.

  my $self = shift;
  my $other = shift;  # could ignore

  return $self->length();
}

sub union {
  my $class = shift;
  # returns a new item (union of the argument items)

  my @members = @_;
  croak $class, "->union given 0 elements" unless @members;
  for (@members) {
    croak "arg to ",$class, "->union not a $class"
      unless ref $_ and $_->isa($class);
  }
  return $members[0] if @members == 1;

  return Sentence::Union->new(@members);
}

sub intersection {
  my $class = shift;
  # returns a new item (intersection of the argument items)

  my @members = @_;
  croak $class, "->intersection given 0 elements" unless @members;
  for (@members) {
    croak "arg to ",$class, "->intersection not a $class"
      unless ref $_ and $_->isa($class);
  }
  return $members[0] if @members == 1;

  return Sentence::Intersection->new(@members);
}

sub element_weight {
  my $self = shift;
  my $name = shift;
  return $self->{elements}{$name} || 0;
}

sub elements {
  my $self = shift;
  return keys %{$self->{elements}};
}

package Sentence::Composite;
use strict;
use warnings;
use Carp;
our @ISA = 'Sentence';
# class for Sentence objects that have been inferred from other
# sentence objects, e.g. unions (merging references) and intersections
# (matching refs to hyps)

# Composite class doesn't have any of the extraction abilities of any
# other Sentence subclass; also ATM can't be further combined with
# other sentences. Could this change?

# ATM no real methods in this class; this is a branching of the class
# hierarchy to separate from the Sentence::* subclasses that actually
# know how to extract elements from real sentences

sub new_from_string {
  my $class = shift;
  croak "$class cannot ->new_from_string because it isa Sentence:;Composite";
}

sub count_items {
  my $class = shift;
  croak "$class cannot ->count_items because it isa Sentence:;Composite";
}

package Sentence::Union;
use strict;
use warnings;
use Carp;
our @ISA = 'Sentence::Composite';

sub length {
  my $self = shift;
  my $class = ref $self;
  carp "called ->length() on a $class object; poorly defined";
  return $self->{_lengths}[0];
}
sub min_diff_length {
  # return length of self that has min diff WRT other
  my $self = shift;
  my $other = shift;

  croak "no _lengths defined in ", ref $self, " object!"
    unless defined $self->{_lengths};

  my $other_length = $other->length();

  # compare other-length to all lengths in self
  # return self-length that has smallest diff

  my ($best_diff, $best_length);
  for my $len (@{$self->{_lengths}}) {
    my $diff = abs( $_ - $other_length );
    if (not defined $best_diff or $diff < $best_diff) {
      $best_diff = $diff; $best_length = $_;
    }
  }
  return $best_length;
}

sub new {
  my $class = shift;
  # new multi-item. Store internal _lengths key
  my @members = @_;

  my %items;
  my @lengths;

  for my $arg (@members) {
    push @lengths, $arg->length();
    for my $elt ($arg->elements) {
      if (not defined $items{$elt} or
	  $arg->element_weight($elt) > $items{$elt} ) {
	$items{$elt} = $arg->element_weight($elt);
      }
    }
  }
  my $self = bless { elements => \%items, _lengths => \@lengths }, $class;
  return $self;
}

package Sentence::Intersection;
our @ISA = 'Sentence::Composite';

sub new {
  my $class = shift;
  my @members = @_;
  my %items;

  # look at every unique key
  use List::MoreUtils 'uniq';
  my @unique_keys = uniq map {$_->elements} @members;
  for my $elt (@unique_keys) {
    my @values = map {$_->element_weight($elt) || 0} @members;
    use List::Util 'min';
    my $val = min (@values);
    $items{$elt} = $val if $val > 0;
  }
  my $self = bless { elements => \%items }, $class;

}


1;
