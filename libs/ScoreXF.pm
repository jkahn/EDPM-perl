package ScoreXF;
use base 'Score';
use strict;
use warnings;
use Carp;

use Statistics::Descriptive;

sub from_cache_string {
  my $class = shift;
  my $line = shift;
  my @subscores = split " ", $line;
  my %scorers;
  for my $subscore (@subscores) {
    my ($name, $substats) = ($subscore =~ /^(\S+)=\((\S+)\)$/);
    my ($hyp, $ref, $overlap) = split /,/, $substats;
    $scorers{$name} =
      ScoreXF::Subscore->new_from_totals(hyptotal => $hyp,
				reftotal => $ref,
				overlap => $overlap);
  }
  return bless {scorers => \%scorers}, $class;
}

sub to_cache_string {
  my $self = shift;
  my $class = ref $self;
  my @scores;
  for my $component ($class->list_cacheable_components) {
    push @scores, "$component=" . $self->{scorers}{$component}->to_string();
  }
  return join " ", @scores;
}

sub combine {
  my $class = shift;
  my @xfs = @_;

  my $self = bless {}, $class;
  my @components = $class->list_components();
  for my $component (@components) {
    my @scorers = map { $_->{scorers}{$component} } @xfs;
    my $scorer = ScoreXF::Subscore->combine( @scorers );
    $scorer->{type} = $component;
    $self->{scorers}{$component} = $scorer;
  }
  return $self;
}

sub score_monobin {
  # F measure putting all components in one bin
  my $self = shift; my $class = ref $self;
  my %args = @_;
  my ($hyptotal, $reftotal, $overlap);
  for my $component ($class->list_components()) {
    $hyptotal += $self->{scorers}{$component}{hyptotal};
    $reftotal += $self->{scorers}{$component}{reftotal};
    $overlap  += $self->{scorers}{$component}{overlap};
  }
  my $scorer =
    ScoreXF::Subscore->new_from_totals(hyptotal => $hyptotal,
				       reftotal => $reftotal,
				       overlap  => $overlap,);

  return 0 if $scorer->precision == 0;
  return 0 if $scorer->recall == 0;

  my $stats = Statistics::Descriptive::Full->new();
  $stats->add_data($scorer->precision(), $scorer->recall());

  return $stats->harmonic_mean();
}

sub score_multibin {
  # harmonic mean across p,r of subscorers
  my $self = shift;
  my %args = @_;
  my $stats = Statistics::Descriptive::Full->new();

  my $class = ref $self;

 COMPONENT:
  for my $component ($class->list_components()) {
    my $subscore = $self->{scorers}{$component};
    if (not defined $subscore) {
      confess "don't recognize component '$component'?";
    }
    if ($subscore->has_null_ref()) {
      # carp "found null reference in score $component, $self->{id}";
      if ($subscore->has_nonnull_hyp()) {
	$stats->add_data(0,0);
      }
      # if both hyp and ref have zero, just skip this one.
      next COMPONENT;
    }
    # if any p,r go to zero, then harmonic mean value should go to zero
    # thus return 0 if any p,r == 0.

    # doesn't introduce any discontinuities.
    $stats->add_data($subscore->precision(),
		     $subscore->recall() );
  }
  my @data = $stats->get_data();
  if (not @data) {
    return 1;  # 0 found on all subscores, also 0 hypothesized. well done!
  }

  if (grep { $_ == 0 } @data) {
    return 0;  # the limit as any precision or recall reaches zero
  }

  return $stats->harmonic_mean();
}

sub new {
  my $class = shift;
  my %args = @_;
  # scorers are part of %args
  return bless \%args, $class;
}
sub list_components {
    my $class = shift;
    croak "class $class didn't come up with a list of components";
}


package ScoreXF::Subscore;
use strict;
use warnings;
use Carp;

sub combine {
  my $class = shift;
  my $self = bless {}, $class;
  use List::Util 'sum';
  $self->{hyptotal} = sum map {($_->{hyptotal} || 0)} @_;
  $self->{reftotal} = sum map {($_->{reftotal} || 0)} @_;
  $self->{overlap} = sum map {$_->{overlap}} @_;
  return $self;
}
sub has_nonnull_hyp {
  my $self = shift;
  return ($self->{hyptotal} != 0);
}
sub has_null_ref {
  my $self = shift;
  return ($self->{reftotal} == 0);
}
sub new {
  my $class = shift;
  my %args = @_;

  my $self = bless \%args, $class;

  $self->{hyptotal} = sum (values %{$self->{translation}}) || 0;

  my @ref_sizes =
    map { sum (values %{$_}) } @{$self->{references}};
  my @ref_diffs =
    map { abs( ($_ || 0) - ($self->{hyptotal}||0) ) } @ref_sizes;

  use List::Util 'min';
  use List::MoreUtils 'first_index';

  my $mindiff = min @ref_diffs;

  my $minidx = first_index { $_ == $mindiff } @ref_diffs;
  $self->{reftotal}  = ($ref_sizes[$minidx] || 0);

  $self->{overlap} = $self->overlap();

  return $self;
}

sub new_from_totals {
  my $class = shift;
  my %args = @_;
  return bless \%args, $class;
}

sub overlap {
  my $self = shift;
  my $overlap = 0;
  for my $token (keys %{$self->{translation}}) {

    my @ref_cts =
      map { $_->{$token} || 0 } @{$self->{references}};

    my $trans_count = $self->{translation}{$token};

    use List::Util 'min', 'max';
    $overlap += min ($trans_count, max (@ref_cts) );
  }
  return $overlap;
}

sub precision {
  my $self = shift;
  if ($self->{hyptotal} == 0) {
    return 0;
  }
  return ($self->{overlap} / $self->{hyptotal});
}

sub recall {
  my $self = shift;
  if ($self->{reftotal} == 0) {
    # QUESTION: is returning 1 right?
    carp "hm, seem to have found a recall subscore ",
      "with 0 denominator and non-zero numerator";
    return 1;
  }
  return ($self->{overlap} / $self->{reftotal});
}

sub to_string {
  my $self = shift;
  return sprintf '(%.5g,%.5g,%.5g)',
    $self->{hyptotal}, $self->{reftotal}, $self->{overlap};
}

1;
