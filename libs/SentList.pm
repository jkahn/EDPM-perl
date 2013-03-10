package SentList;
use strict;
use warnings;
use Carp;

sub new {
  my $class = shift;
  my %args = @_;
  return bless \%args, $class;
}

sub ids {
  my $self = shift;
  return map {$_->{id}} $self->lines;
}

sub lines {
  my $self = shift;
  return @{$self->{lines}};
}
##################################################################
package SentList::Forest;
use strict;
use warnings;
use Carp;
our (@ISA) = 'SentList';

sub new_from_file {
  my $class = shift;
  my %args = @_;
  my $file = $args{file};

  my @raw;
  {
    local $/ = "\n\n";
    open my $fh, "<", $file
      or die "couldn't open Deps file '$file': $!\n";
    binmode $fh, ":gzip" if $ScoreConfig::COMPRESS_SYNTAX_CACHE;
    @raw = <$fh>;
    close $fh
      or die "Couldn't close Deps file '$file': $!\n";
  }

  my @lines;
  my %idlists;
  my $latest_line;

 TREE:
  while (my $rawdeps = shift @raw) {
    my $deptree = Deps->from_text($rawdeps);

    my $id = $deptree->id();
    my $hypid = $deptree->hypid();
    if (defined $latest_line and $latest_line->id() eq $id) {
      $latest_line->addhyp(hyp => $hypid, deptree => $deptree);
      next TREE;
    }

    # otherwise not the same Dep::Forest
    my $line = Dep::Forest->new(%args, id => $id);
    $line->addhyp(hyp => $hypid, deptree => $deptree);

    if ($args{hyplist} and defined $idlists{$id} and @{$idlists{$id}} > 0) {
      carp "found two forests with id $id in hyp file $file";
    }

    # record this one in the hash, and the list
    push @{$idlists{$id}}, $line;
    push @lines, $line;
    $latest_line = $line; # remember this one, we'll add more hyps to
                          # it
  }

  return $class->new(lines => \@lines, ids => \%idlists, file => $file);
}
sub forests_matching_id {
  my $self = shift;
  my $id = shift;
  confess "no id passed to forests_matching_id on file '$self->{file}'" unless defined $id;
  confess "no id $id found in forest file '$self->{file}'" unless defined $self->{ids}{$id};
  return @{$self->{ids}{$id}};
}

##################################################################
package SentList::Text;
use strict;
use warnings;
use Carp;
our (@ISA) = 'SentList';

sub new_from_file {
  my $class = shift;
  my %args = @_;

  croak "file arg not passed" unless exists $args{file};

  my $file = $args{file};


  confess "file arg not defined" unless defined $file;

  open my $fh, "<", $file
    or die "couldn't open file '$file': $!\n";

  my @lines;
  my %idlists;
  while (<$fh>) {
    my ($text, $id) = /^(.*)\s\((\S+)\)\s*$/;

    my $line = Line::Text->new(text => $text, linenum => $., id => $id);

    if ($args{hyplist} and defined $idlists{$id} and @{$idlists{$id}} > 0 ) {
      carp "found two items with id $id in hyplist";
    }

    push @{$idlists{$id}}, $line;
    push @lines, $line;

  }
  close $fh
    or die "couldn't close rawfile '$file': $!\n";

  return $class->new(lines => \@lines, ids => \%idlists);
}

sub text_lines {
  my $self = shift;
  return map {$_->{text}} $self->lines;
}

sub text_matching_id {
  my $self = shift;
  my $id = shift;
  return map {$_->text} @{$self->{ids}{$id}};
}

sub blank_ids {
  my $self = shift;
  return grep { $_->is_blank } $self->lines;
}

sub nonblank_lines {
  my $self = shift;
  return grep { not $_->is_blank } $self->lines;
}
##################################################################
package Line;
sub new {
  my $class = shift;
  my %args = @_;
  return bless \%args, $class;
}

sub id {
  my $self = shift;
  return $self->{id};
}

#################################
package Line::Text;
our @ISA = 'Line';
use strict;
use warnings;

sub text {
  my $self = shift;
  return $self->{text};
}
sub is_blank {
  my $self = shift;
  return $self->{text} =~ /^\s*[[:punct:]\s]*\s*$/;
}

1;
