package BLEU;
use strict;
use warnings;

use Carp;

use base 'Score';
use ScoreConfig;

use constant PARANOID => 0;
use NGram;

our @CLASSES; # list of registered subclasses

sub get_name {
  # generate default name for variant 
  my $class = shift;
  my %args = @_;

  my @items = ('BLEU', $args{n});

  return join '::', @items;
}

sub register_variant {
  my $class = shift;
  my %args = @_;

  my $code = "package $args{name};\n";
  $code .= "our \@ISA = '$class';\n";
  $code .= "sub max_n { $args{n} }\n";
  eval $code;
  if ($@) {
    warn "evaluating code:\n";
    warn "$code\n\n";
    croak "failed with error '$@'";
  }

  push @CLASSES, $args{name};
}

sub list_classes {
  return @CLASSES;
}
# use baseclass write_cachefile

# use baseclass read_cachefile

sub new_from_string {
  my $class = shift;
  my %args = @_;
  my %behavior = (normalize => 1, lowercase => 0);

  my $translation = NGram->new(text => $args{trans}, %behavior);
  my @refs = map { NGram->new(text => $_, %behavior) } @{$args{ref}};

  my @overlaps =
    NGram->overlaps(ref => \@refs, trans => $translation);
  my $best_ref_length =
    NGram->best_ref_length(trans => $translation, ref => \@refs);
  my @trans_totals = $translation->totals();


  return $class->new(ref_length => $best_ref_length,
		     trans_length => $translation->length(),
		     trans_totals => \@trans_totals,
		     overlap => \@overlaps,
		    id => $args{id});
}

sub from_cache_string {
  my $class = shift;
  my $string = shift;
  my ($reflen, $translen, @ngramstats) = split " ", $string;

  # remove human-readable markup
  $reflen =~ s/^reflen:// or carp "reflen '$reflen' doesn't look as expected";
  $translen =~ s/^tlen:// or carp "tlen '$translen' doesn't look as expected";

  my (@trans_totals, @overlap);
  for (@ngramstats) {
    my ($n, $overlap, $trans_total) = m{^(\d+):(\d+)/(\d+)$};
    carp "$class ngramstat '$_' weird/unexpected"
      unless defined $trans_total;

    $trans_totals[$n] = $trans_total || 0;
    $overlap[$n] = $overlap;
  }

  return $class->new(ref_length => $reflen,
		     trans_length => $translen,
		     trans_totals => \@trans_totals,
		     overlap => \@overlap);
}

sub to_cache_string {
  my $self = shift;
  my $prefix = sprintf "reflen:%d tlen:%d",
    $self->{ref_length}, $self->{trans_length};

  my @ngramstats;
  for my $n (1 .. $ScoreConfig::MAX_NGRAM) {
    push @ngramstats, sprintf "%d:%d/%d",
      $n, $self->{overlap}[$n], $self->{trans_totals}[$n];
  }
  return join (" ", $prefix, @ngramstats);
}

sub combine {
  my $class = shift;

  my %args;
  if (ref $_[0] eq 'HASH') {
    %args = %{ shift @_ };
  }

  if (PARANOID) {
    carp "non-$class in arglist"
      if grep { not $_->isa($class) } @_;
  }


  use List::Util 'sum';
  $args{trans_length} = sum map {$_->{trans_length}} @_;
  $args{ref_length}   = sum map {$_->{ref_length}} @_;

  for my $n (1 .. $ScoreConfig::MAX_NGRAM) {
    $args{trans_totals}[$n] = sum map {$_->{trans_totals}[$n]} @_;
    $args{overlap}[$n]      = sum map {$_->{overlap}[$n]} @_;
  }

  return $class->new(%args);
}

sub suffix {
  return 'bleu'; # even for subclasses
}

sub score {
  my $self = shift;

  my %args = @_;

  my $class = ref $self;

  if ($self->{trans_length} == 0) {
    return 0;
  }

  # Compute accuracies at each $n specified
  my @accuracies;
  confess "no max_n defined" unless $class->can('max_n');
  for my $n (1 .. $class->max_n) {
    my $hypothesized = ($self->{trans_totals}[$n] || 0);
    my $correct = ($self->{overlap}[$n] || 0);
    if ($hypothesized == 0) {
      $accuracies[$n] = $ScoreConfig::BLEU_EPSILON;
    }
    else {
      $accuracies[$n] = $correct/$hypothesized;
    }
  }
  shift @accuracies; # discard undefined 0-grams

  use List::Util 'sum';


  # combine the accuracies
  my $sum_log_accuracy =
    sum map { my_log( $_ ) } @accuracies;

  my $avg_log_acc = $sum_log_accuracy / $class->max_n;

  # compute a brevity penalty
  my $brevity_penalty = 1;
  if ($self->{trans_length} < $self->{ref_length}) {
    $brevity_penalty =
      exp(1 - $self->{ref_length}/$self->{trans_length});
  }

  return $brevity_penalty * exp( $avg_log_acc );
}
#################################

sub new {
  my $class = shift;
  my %args = @_;
  carp "no trans_length found"
    unless defined $args{trans_length};
  carp "no ref_length found"
    unless defined $args{ref_length};
  carp "no trans_totals found"
    unless $args{trans_totals};
  carp "no overlap found"
    unless $args{overlap};

  return bless \%args, $class;
}

sub my_log {
  return -9999999999 unless $_[0];
  return log($_[0]);
}


1;
