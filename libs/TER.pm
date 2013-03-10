package TER;
use strict;
use warnings;

use Carp;

use base 'Score';
use ScoreConfig;

use constant PARANOID => 0;

sub write_cachefile {
  my $class = shift;
  die "write_cachefile not supported for $class";
}

sub write_cachefile_from_raw {
  my $class = shift;
  my %args = @_;

  if (keys %{$args{skips}{TER}}) {
    croak "don't know how to deal with skips for TER";
  }

  my $out = $args{cache};
  my $err = $args{err};
  if (not defined $err) {
    $err = $out . ".err";
  }
  my $translation = $args{trans};
  my @references = @{$args{ref}};
  my @corrected;
  if (defined $args{corr}) {
    @corrected = @{$args{corr}};
  }

  my ($reference, $corrected);  # the files for compute

  {
    croak "can't handle multiple ref files right now"
      if @references > 1;

    croak "no references given"
      unless @references;

    croak "ref $references[0] not a file"
      unless -f $references[0];

    # TO DO: construct tempfile of all references
    $reference = $references[0];
  }

  if (defined $args{corr}) {
    croak "other than one corr node given" unless @corrected == 1;
    $corrected = $corrected[0];
  }

  if (not defined $ScoreConfig::TERCOM_PERL) {
    croak "\$ScoreConfig::TERCOM_PERL not defined!";
  }
  if (not -x $ScoreConfig::TERCOM_PERL) {
    croak "\$Config::TERCOM_PERL '$ScoreConfig::TERCOM_PERL'",
      " not an executable file";
  }

  croak "translation arg not defined"
    unless defined $translation;
  croak "translation => $translation not a file"
    unless -f $translation;

  my (@args) =
    ($ScoreConfig::TERCOM_PERL,
     '-h' => $translation,
     '-o' => 'sum',  # only interested in summary file
     '-s', '-N',     # case sensitive, use MTEval tokenization
    );

  # TER and HTER have different ways of passing the human-targeted and
  # a-priori references to the script.  (TER ignores the
  # human-targeted reference entirely).
  push @args, $class->choose_ref_args(tref => $corrected, ref => $reference);

  # warn "command: `@args`\n" if $verbose;
  my $exit_code = system ("@args 1>$err");

  if ($exit_code) {
    die "system '@args' failed: $?\n";
  }
  use File::Copy 'move';
  move ("$translation.sys.sum" => $out)
    or die "couldn't move '$translation.sys.sum' to '$out': $!\n"; 
}

sub choose_ref_args {
  my $class = shift;
  my %args = @_;
  # TER: ignore tref arg entirely, pass a-priori ref as -r argument to script
  return "-r" => $args{ref};
}

sub read_cachefile {
  my $class = shift;
  my %args = @_;

  my $file = $args{cache};

  open my $fh, "<", $file
    or croak "can't open cache $class file '$file': $!\n";

  my @segs;
  while (<$fh>) {
    next if /^Hypothesis File:/;
    next if /^Reference File: /;
    next if /^Ave-Reference File: /;
    next if /^Sent Id/;
    next if /^-----/;
    next if /^\s*$/;  # skip blank lines too
    next if /^TOTAL/;

    chomp;
    my ($seg, $ins, $del, $sub, $shft, $wdsh, $numer, $numwd, $ter)
      = split /\s+\|\s+/;

    my $self = $class->new(edits => $numer, words => $numwd, id => $seg);

    if (PARANOID) {
      my $computed = sprintf ("%.3f",$self->score() * 100);
      carp "score mismatch? ($numer/$numwd == $computed != $ter) ",
	"on line $. of $class file '$file'\n"
	if  ($computed != $ter);
    }
    push @segs, $self;
  }
  close $fh
    or croak "can't close cache $class file '$file': $!\n";

  return @segs;
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
  $args{edits} = sum map {$_->{edits}} @_;
  $args{words} = sum map {$_->{words}} @_;

  $args{id} = join "\n", map {$_->{id}} @_;

  return $class->new(%args);
}

sub score {
  my $self = shift;
  return 0 if ($self->{words} == 0);
  return $self->{edits} / $self->{words};
}

#################################
sub new {
  my $class = shift;

  my %args = @_;
  croak "no edits arg given" unless defined $args{edits};
  croak "no words arg given" unless defined $args{words};

  my $self = bless \%args, $class;
  return $self;
}

##################################################################
package HTER;
use warnings;
use strict;
use Carp;
our @ISA = 'TER';

sub choose_ref_args {
  my $class = shift;
  my %args = @_;
  if (not defined $args{tref}) {
    confess "HTER called without a targeted reference";
  }
  # HTER:
  return "-r" => $args{tref}, "-a" => $args{ref};
}
## HTER doesn't need any additional behavior except a different
## argument structure to the script

1;
