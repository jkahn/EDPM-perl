package MEDLSum;  # Munkres Expected Dependency Link Sum
use strict;
use warnings;
use Carp;
use base 'Score';

sub sent_class {
  my $class = shift;
  return 'Sentence';
}

sub new_from_string {
  my $class = shift;
  my %args = @_;
  my $sent_class = $class->sent_class();
  my $hyp_sent = $sent_class->new(string => $args{trans});
  my @ref_sents =  map { [ $sent_class->new(string => $_) ] } @{$args{ref}};

  my $hyp = $counter->new($hyp_sent);
  my @refs = map { $counter->new($_) } @ref_sents;

  # Possible algorithms here:

  # A: separate Munkres match vs each of the references, then choose
  # the best match for each type in hyp.

  # B: Construct "union-reference", which is max of all counts. Then
  # do Munkres match between hyp and union-ref

  # B is more appealing to me.

  # either strategy is vulnerable to generation of second synonyms in
  # place of untranslateable words.

  # Is this a fundamental problem with multiple references? perhaps in
  # the long run aligning references with each other and discount
  # second picks on tokens that align to already picked tokens in a
  # different ref.  computationally hard and perhaps unreliable?

  # compute hyp_count
  my $hyp_count = $hyp->length();


  # choice B: construct union ref
  my $unionref = $sent_class->union(@refs);

  my $best_ref_length = $unionref->min_diff_length($hyp);


  # Kuhn-Munkres match when all weights are zero or identity
  my $correct_set = $sent_class->intersection($hyp, $unionref);

  my $self =
    bless { correct => $correct_set->length(),
	    hyp_count => $hyp_count,
	    ref_count => $best_ref_length }, $class;
  return $self;
}

sub score {
  my $self = shift;

  if ($self->{hyp_count} == 0) {
    return 1 if $self->{ref_count} == 0;
    return 0;
  }
  if ($self->{ref_count} == 0) {
    return 1 if $self->{hyp_count} == 0;
    return 0;
  }

  my $precision = $self->{correct} / $self->{hyp_count};
  my $recall = $self->{correct} / $self->{ref_count};

  my $F = (2 * $precision * $recall) / ($precision + $recall);

  return $F;
}

sub combine {
  my $class = shift;
  my @elements = @_;
  use Scalar::Util 'sum';
  my $correct   = sum map { $_->{correct}   } @elements;
  my $hyp_count = sum map { $_->{hyp_count} } @elements;
  my $ref_count = sum map { $_->{ref_count} } @elements;
  return bless { correct => $correct,
		 hyp_count => $hyp_count,
		 ref_count => $ref_count }, $class;
}

sub suffix {
  my $class = shift;
  return "medlsum";
}
sub markup {
  my $class = shift;
  return "";  # head-finding status? whether hungarian
}

sub to_cache_string {
  my $self = shift;
  return sprintf '%.5g/%.5g[ref],%.5g[hyp]',
    $self->{correct}, $self->{ref_count}, $self->{hyp_count};
}

sub from_cache_string {
  my $class = shift;

  my $string = shift;
  my ($link_wt, $ref_items, $hyp_items) =
    $string =~ m{^(\S+)/(\S+)\[ref\],(\S+)\[hyp\]$};
  croak "didn't understand string $string"
    unless defined $hyp_items;
  my $self = bless { correct => $link_wt,
		     ref_count => $ref_items,
		     hyp_count => $hyp_items }, $class;
  return $self;
}

sub null_score {
  my $class = shift;
  my %args = @_;
  # only use if we're skipping certain values.
  croak "null_score not implemented";
}

1;

