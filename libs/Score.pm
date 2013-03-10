package Score;
use strict;
use warnings;

use Carp;
use ScoreConfig;

sub compute_cachename {
  my $class = shift;
  my (%args) = @_;
  use File::Basename 'fileparse';
  my ($stem, $dir, $raw) = fileparse($args{trans}, @ScoreConfig::RAW_SUFFIXES);

  my $refid;
  if (defined $args{refid}) {
    $refid = $args{refid};
  }
  else {
    $refid = scalar @{$args{ref}} . "ref";
  }

  my $suffix = $class->suffix();

  my $markup = $class->markup();

  return File::Spec->catfile($dir, "$stem-$refid$markup.$suffix");
}

sub suffix {
  my $class = shift;
  return lc $class;
}
sub markup {
  my $class = shift;
  return "";
}


# TER overrides this. 
sub write_cachefile_from_raw {
  my $class = shift;
  my %args = @_;

  my $cache = $args{cache};
  delete $args{cache};

  my @scores = $class->objects_from_raw_files(%args);
  $class->write_cachefile($cache, @scores);
}

# Assumes that scores have simple to_cache_string for linewise
# out. TER doesn't support this alone.
sub write_cachefile {

  my $class = shift;
  my $cachefile = shift;

  open my $cachefh, ">", $cachefile
    or die "couldn't open cachefile $cachefile: $!\n";

  for (@_) {
    print $cachefh $_->id(), " ", $_->to_cache_string(), "\n";
  }
  close $cachefh
    or die "couldn't close cachefile: $!\n";
}

# overridden by anything that needs to read batches non-linewise: DPF, TER
# batch these.  override objects_from_raw_files to
# do things batchwise
sub objects_from_raw_files {
  my $class = shift;
  my %args = @_;

  my $transfile = $args{trans};
  my @reffiles = @{$args{ref}};

  use SentList;
  my $trans_list =
    SentList::Text->new_from_file(hyplist => 1, file => $args{trans});
  my @reflists =
    map { SentList::Text->new_from_file(hyplist => 0, file => $_) }
      @reffiles;

  my @scores;

 ID:
  for my $id ($trans_list->ids) {
    my ($trans) = $trans_list->text_matching_id($id);

    my @refs = map { $_->text_matching_id($id) } @reflists;

    if ($args{skips}{$class}{$id}) {
      push @scores, $class->null_score(trans =>  $trans, refs => \@refs);
      next ID;
    }
    my $score = $class->new_from_string(trans => $trans, ref => \@refs,
				       id => $id);
    push @scores, $score;
  }

  # warn "found extra refs" if grep { defined scalar <$_> } @reffhs;
  return @scores;
}

sub null_score {
  my $class = shift;
  croak "class $class hasn't implemented null_score, but needed it";
}

# Assumes cache is line-oriented.  override entire read_cachefile method if
# output not line-oriented (as in TER, but not DPF, NGF, BLEU).
sub read_cachefile {
  my $class = shift;
  my %args = @_;

  my $file = $args{cache};

  open my $fh, "<", $file
    or croak "can't open cache $class file '$file': $!\n";

  my @segs;
  while (<$fh>) {
    /^(\S+)\s+(.*)$/ or carp "couldn't figure out id";
    my ($id, $text) = ($1, $2);

    my $new = $class->from_cache_string($text);
    $new->id($id);
    push @segs, $new;
  }
  close $fh
    or croak "can't close cache $class file '$file': $!\n";

  return @segs;
}

sub new_from_string {
  my $class = shift;
  # expect (ref => [], trans => $string, %args);
  croak "class $class has not implemented new_from_string ",
    "but is being asked to make a score_from_strings";
}

sub from_cache_string {
  my $class = shift;
  croak "class $class has not implemented from_cache_string " ,
    "but is trying to handle line '$_[0]'";
}
sub to_cache_string {
  my $class = shift;
  croak "class $class has not implemented to_cache_string " ,
    "but is being asked to write a line-oriented cache string";
}

sub combine {
  my $class = shift;
  croak "class $class doesn't have a combine method,",
    " but it's derived from the Score interface, which requires it!"
}

sub score {
  my $self = shift;
  my $class = ref $self;
  croak "class $class doesn't have a score method,",
    " but it's derived from the Score interface, which requires it!"
}

sub id {
  my $self = shift;
  my $arg = shift;
  if (defined $arg) {
    $self->{id} = $arg;
  }
  return $self->{id};
}


1;
