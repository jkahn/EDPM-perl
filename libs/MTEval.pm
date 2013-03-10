package MTEval;
## Package for parsing and manipulating the NIST MT files (as of
## 2008), cf: documentation at
## http://www.nist.gov/speech/tests/metricsmatr/2008/

use strict;
use warnings;
use Carp;

our $DEBUG = 0;

sub new {
  my $class = shift;
  my %args = @_;

  use XML::Twig;
  my $parser = XML::Twig->new();

  my ($tset, @refsets);
  if ($args{file}) {
    croak "can't have both file and tfile"
      if defined $args{tfile};
    croak "can't have both file and reffile"
      if defined $args{reffile};
    $parser->parsefile($args{file});
    my $fileroot = $parser->root();
    croak "file does not seem to have an enclosing 'mteval' tok"
      unless $fileroot->tag() eq 'mteval';

    croak "file seems to have other than 1 tstset"
      if $fileroot->children_count('tstset') != 1;

    croak "no refsets found in $args{file}"
      unless $fileroot->children_count('refset');

    $tset = MTEval::Set->new($fileroot->children('tstset'));
    @refsets = map {MTEval::Set->new($_)} $fileroot->children('refset');
  }
  elsif (not defined $args{tfile}) {
    croak "no tfile defined";
  }
  elsif (not defined $args{reffile}) {
    croak "no reffile defined";
  }
  else {
    # better have both tfile and reffile
    $parser->parsefile($args{tfile});
    my $tfileroot = $parser->root();
    croak "tfile does not seem to have an enclosing 'mteval' tok"
      unless $tfileroot->tag() eq 'mteval';

    croak "tfile seems to have other than 1 tstset"
      if $tfileroot->children_count('tstset') != 1;
    $tset = MTEval::Set->new($tfileroot->children('tstset'));

    $parser->parsefile($args{reffile});
    my $rfileroot = $parser->root();
    croak "no refsets found in $args{file}"
      unless $rfileroot->children_count('refset');
    @refsets = map {MTEval::Set->new($_)} $rfileroot->children('refset');

  }

  return bless { tset => $tset, refs => \@refsets }, $class;
}

sub tset {
  my $self = shift;
  return $self->{tset};
}

sub refsets {
  my $self = shift;
  return @{$self->{refs}};
}
sub build {
  my $class = shift;
  my $fh = shift;
  my @files = @_;

  print $fh '<?xml version="1.0" encoding="UTF-8"?>', "\n";

  print $fh '<!DOCTYPE mteval SYSTEM ',
    '"ftp://jaguar.ncsl.nist.gov/mt/resources/mteval-xml-v1.0.dtd">', "\n";
  print $fh '<mteval>';

  for my $f (@files) {
    open my $infh, "<", $f
      or die "can't open file '$f' for reading: $!\n";
    while (<$infh>) {
      s{<DOC}{<doc}g;
      s{</DOC}{</doc}g;
      print $fh $_;
    }
    close $infh
      or die "can't close file '$f' after reading: $!\n";
  }
  print $fh '</mteval>';
  $fh->flush();
  return $fh;
}

package MTEval::Set;
use strict;
use warnings;
use Carp;
sub new {
  my $class = shift;
  my $root = shift;

  my %args;
  for (qw( setid srclang trglang ) ) {
    $args{$_} = $root->att($_);
  }

  croak "$class set has non 'doc' children"
    unless $root->children_count() == $root->children('doc');

  my @docs = map {MTEval::Doc->new($_)} $root->children('doc');

  return bless {%args, docs => \@docs}, $class;
}
sub write_rawfile {
  my $self = shift;
  my $raw = shift;

  use File::Temp;
  my $rawfh = File::Temp->new();

  for my $doc ( $self->docs() ) {
    for my $seg ( $doc->segs() ) {
      print $rawfh $seg->raw();
    }
  }
  $rawfh->flush();
  if (system ('cmp', $rawfh, $raw)) {
    # cmp returned 1, they're different
    use File::Copy 'move';
    move $rawfh, $raw
      or die "couldn't move $rawfh to $raw: $!\n";
  }
  # otherwise don't touch the file. keep timestamps easy.
}

sub setid {
  my $self = shift;
  return $self->{setid};
}
sub sysid {
  my $self = shift;
  use List::MoreUtils 'uniq';
  my @uniq_sysids = uniq map {$_->sysid()} $self->docs();
  if (@uniq_sysids > 1) {
    carp "found >1 unique sysid (@uniq_sysids) in docs series";
  }
  return $uniq_sysids[0];
}

sub docs {
  my $self = shift;
  return @{$self->{docs}};
}
#################################
package MTEval::Doc;
use strict;
use warnings;
use Carp;
sub new {
  my $class = shift;
  my $root = shift;
  my %atts = map { $_ => $root->att($_) } (qw( docid genre sysid ));

#   croak "doc has non-seg children"
#     unless $root->children_count() == $root->children_count('seg');

  my @segments = map {MTEval::Segment->new($_, $atts{docid})} $root->descendants('seg');

  my $self = bless {%atts, segs => \@segments}, $class;
}
sub sysid {
  my $self = shift;
  return $self->{sysid};
}
sub segs {
  my $self = shift;
  return @{$self->{segs}};
}
#################################
package MTEval::Segment;
use strict;
use warnings;
use Carp;

sub new {
  my $class = shift;
  my $root = shift;
  my $docid = shift;
  my $segid = $root->att('id');

  croak "seg has >1 subelement"
    unless $root->children_count() == 1;
  my $textnode = $root->first_child();

  croak "non-text element found within seg"
    unless $textnode->is_pcdata();

  my $text = $textnode->pcdata();
  croak "text for seg not found"
    unless defined $text;

  return bless { docid => $docid, segid => $segid, text => $text }, $class;
}
sub raw {
  # generates the raw form needed for EDPM
  my $self = shift;
  my %args = @_;
  return "$self->{text} ($self->{docid}/$self->{segid})\n";
}


1;
