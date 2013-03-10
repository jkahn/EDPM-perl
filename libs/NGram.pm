package NGram;

use strict;
use warnings;
use Carp;

use ScoreConfig;

sub new {
  my $class = shift;
  my %args = @_;
  my $text = $args{text};
  delete $args{text};

  my $self = bless \%args, $class;

  if ($args{normalize}) {
    $text = $class->normalize($text);
  }

  my @words = split " ", $text;
  if ($args{lowercase}) {
    @words = map { lc } @words;
  }

  $self->{words} = \@words;

  for my $n (1 .. $ScoreConfig::MAX_NGRAM) {
    for my $start ( 0 .. (@words - $n) ) {
      my @ngram_words = @words[$start .. ($start + $n - 1)];
      my $ngram = join " ", @ngram_words;
      $self->{ngrams}[$n]{$ngram}++;
    }
  }
  return $self;
}
sub normalize {
  my $class = shift;
  local $_ = shift;
  $_ = " $_ ";
  # $text =~ tr/[A-Z]/[a-z]/ unless $preserve_case;
  s/([\{-\~\[-\` -\&\(-\+\:-\@\/])/ $1 /g;
  # tokenize punctuation

  s/([^0-9])([\.,])/$1 $2 /g;
  # tokenize period and comma unless preceded by a digit

  s/([\.,])([^0-9])/ $1 $2/g;
  # tokenize period and comma unless followed by a digit

  s/([0-9])(-)/$1 $2 /g;
  # tokenize dash when preceded by a digit

  s/\s+/ /g; # one space only between words
  s/^\s+//;  # no leading space
  s/\s+$//;  # no trailing space
  return $_;
}
sub totals {
  my $self = shift;

  my @totals;
  for my $n (1 .. $ScoreConfig::MAX_NGRAM) {
    use List::Util 'sum';
    $totals[$n] = (sum values %{$self->{ngrams}[$n]} || 0);
  }
  return @totals;
}

sub best_ref_length {
  my $class = shift;
  my %args = @_;
  my @refs = @{$args{ref}};
  my $trans = $args{trans};

  my $closest_diff;
  my $closest_by_length;
  for my $ref (@refs) {
    my $length_diff =
      abs($trans->length() - $ref->length());
    # keep an eye out for the closest_length
    if (not defined $closest_by_length
	or $length_diff < $closest_diff) {
      $closest_by_length = $ref;
      $closest_diff = $length_diff;
    }
  }
  return $closest_by_length->length();
}

sub length {
    my $self = shift;
    return scalar @{$self->{words}};
}

sub overlaps {
  my $class = shift;
  my %args = @_;
  my @refs = @{$args{ref}};
  my $trans = $args{trans};

  my @overlaps;

  # look at each ngram length
  for my $n (1 .. $ScoreConfig::MAX_NGRAM) {
    # look at each ngram in the translation
    $overlaps[$n] = 0;
    for my $ngram ( keys %{$trans->{ngrams}[$n]}) {
      # count them
      my $trans_ct = ($trans->{ngrams}[$n]{$ngram} || 0);

      # count for each of the translations
      my @refcts = map {$_->{ngrams}[$n]{$ngram} || 0} @refs;

      # cap the count of the translation at the top of the references.
      use List::Util 'max', 'min';
      $overlaps[$n] += min($trans_ct, max(@refcts));
    }
  }
  return @overlaps;
}
1;
