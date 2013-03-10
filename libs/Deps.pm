package Deps;
use strict;
use warnings;
use Carp;

our $DEBUG = 0;
our $VERBOSE = 0;

use ScoreConfig;

our $HFSTEM = "ptb-sem";
our $DEPS_SUFFIX = ".$ScoreConfig::PARSER_NBEST-best.$HFSTEM.deps";
if ($ScoreConfig::COMPRESS_SYNTAX_CACHE) {
  $DEPS_SUFFIX .= ".gz";
}

sub syntax_depsfile {
  # given a raw file, tell me where to put the deps
  my $class = shift;
  my $rawfile = shift;

  use File::Basename 'fileparse';
  my ($stem, $dir, $suffix) = fileparse($rawfile, @ScoreConfig::RAW_SUFFIXES);
  my $out = File::Spec->catfile($dir, "$stem$DEPS_SUFFIX");
  warn "depsfile: $out\n"
    if $VERBOSE;
  return $out;
}

#################################
sub new {
    my $class = shift;
    my %args = @_;

    confess "no root arg given" unless defined $args{root};
    croak "no members arg given" unless defined $args{members};

    return bless \%args, $class;
}
#################################
# member contents
sub confidence {
  my $self = shift;
  my $gamma = shift;
  carp "no gamma defined" unless defined $gamma;
  return $self->{conf} * $gamma;  # confidence is in log space, so
                                  # multiply in order to
                                  # raise-to-power in prob space
}
sub id {
  if (defined $_[1]) {
    $_[0]->{id} = $_[1];
  }
  return $_[0]->{id};
}
sub hypid {
  if (defined $_[1]) {
    $_[0]->{hypid} = $_[1];
  }
  return $_[0]->{hypid};
}
sub length {
    my $self = shift;
    return $#{$self->{members}};
}

sub list_spelled {
  my $self = shift;
  my $component = shift;

  my @out;
  for my $twig ($self->list_twigs(2)) {
    push @out, $twig->spell($component);
  }

  my %counts;
  $counts{$_}++ for (@out);
  return %counts;
}

sub list_twigs {
  my $self = shift;
  my $n = shift;

  if ($n > 2) {
    croak "list_twigs with nodelength > 2 not implemented";
  }
  if ($n < 1) {
    croak "list twigs with nodelength < 1 doesn't make sense";
  }

  my @twigs;

  if (not defined @{$self->{members}}) {
    croak "list_twigs called with no members!";
  }
  for my $word (@{$self->{members}}) {
    next if $word->{word} eq '<root>';
    my @members = $word;
    my $root = $word;

    # this approach will work if $n == 3 for grandparents too but
    # not other subtree configurations
    while (@members < $n) {
      my $parent = $members[-1]->{parent};
      push @members, $parent;
      $root = $parent;
    }
    my $twig = Deps->new(root => $root, members => \@members);
    push @twigs, $twig;
  }
  return @twigs;
}

sub spell {
  my $self = shift;
  my $filter = shift;		# indicates arcs and words to include
  croak "can't call spell with tree > 2 nodes"
    if (@{$self->{members}} > 2);

  croak "one-node calls to spell unimplemented"
    if (@{$self->{members}} == 1);

  my $dependent = $self->{members}[0]{word};
  my $relation  = $self->{members}[0]{modtype};
  my $governor  = $self->{members}[1]{word};

  if ($filter eq 'word-arc-word') {
    return "$dependent =$relation=> $governor";
  } elsif ($filter eq 'word-word') {
    return "$dependent => $governor";
  } elsif ($filter eq 'word-arc') {
    return "$dependent =$relation=>";
  } elsif ($filter eq 'arc-word') {
    return "=$relation=> $governor";
  } elsif ($filter eq 'word') {
    return "$dependent";
  } else {
    croak "unrecognized filter $filter";
  }
}
#################################
sub from_text {
  my $class = shift;
  my $text = shift;

  my (@lines) = split /\n/, $text;
  chomp @lines;

  my $idline = shift @lines;

  my (@words) = map {DepWord->from_text($_)} @lines;


  # push the (non-pronounced) root node onto the list. Conveniently,
  # this occupies the 0-cell of the array, making the 1-based indices
  # all match up.
  unshift @words, DepWord->new(wdindex => 0, word => '<root>',
			       pos1 => 'ROOT', pos2 => 'ROOT');

  # and we need to remember which one is the root
  my $self = $class->new(root => $words[0], members => \@words);

  # update parent pointers for all items
  my @nonroots = @words; shift @nonroots;

  for my $word (@nonroots) {
    $word->{parent} = $self->{members}[$word->{head}];
  }

  # update the id information.
  my ($id, $hypid, $info) =
    ($idline =~ /^#\s*(\S+)\.h(\d+)(\s+.*)?$/);
  carp "no idline found at first line of $text"
    unless defined $hypid;

  $self->id( $id );
  $self->hypid ( $hypid  );

  # only keep the features that match 'conf'
  if (defined $info and CORE::length $info) {
    my @info = split " ", $info;
    for (@info) {
      if (/^conf=(\S+)$/) {
	$self->{conf} = $1;
      }
      else {
	carp "ignoring feature $_ in deptree" if $VERBOSE;
      }
    }
  }
  return $self;
}
sub stringify {
  my $self = shift;
  return join " ", map {$_->{word}} @{$self->{members}};
}
##################################################################
# Conversion utilities
sub convert_treefile_to_depsfile {
  my $class = shift;
  my $in = shift;
  my $out = shift;
  my %args = @_;

  use Lingua::Treebank::HeadFinder;
  my $hftable = $args{hftable};

  if (not defined $hftable) {
    croak "hftable not defined extract_deps";
  }

  if ($VERBOSE) {
    warn "converting $in to $out using $hftable\n";
  }

  my $headfinder =
    Lingua::Treebank::HeadFinder->new(format => 'charniak',
				      file => $hftable);

  open my $infh, "<", $in
    or die "couldn't open treefile '$in' for reading: $!\n";
#   open my $outfh, ">", $out
#     or die "couldn't open depsfile '$out' for writing: $!\n";
  use File::Temp;
  my $out_tmp = File::Temp->new(CLEANUP => (not $DEBUG));
  if ($ScoreConfig::COMPRESS_SYNTAX_CACHE) {
    binmode $infh,  ':gzip';
    binmode $out_tmp, ':gzip';
  }
  local $/ = "\n\n";

  while (my $rawsent = <$infh>) {
    print $out_tmp $class->hyplist_to_depstrings($rawsent, $headfinder), "\n";
  }

  close $infh
    or die "couldn't close treefile '$in' after reading: $!\n";
#   close $out_tmp
#     or die "couldn't close depsfile '$out_tmp' after writing: $!\n";
  $out_tmp->flush();
  use File::Copy 'move';
  move ("$out_tmp", $out)
    or die "couldn't move $out_tmp to $out: $!\n";

  if ($VERBOSE) {
    warn "done converting to $out\n";
  }

}

sub hyplist_to_depstrings {
  my $class = shift;
  my $text = shift;
  my $headfinder = shift;

  my (@lines) = split /\n/, $text;

  # break off information about parse
  my $info = shift @lines;
  my ($numparses, $id) =
    ( $info =~ /^(\d+)\s+(\S+)\s*$/ );
  warn "parse info line at $. '$info' seems wrong -- couldn't get id\n"
    unless defined $id;

  warn "uh-oh -- uneven number of lines in hyplist after info\n"
    if @lines %2;

  warn "uh-oh -- $numparses reported but only " . @lines / 2 . " found\n"
    unless @lines/2 == $numparses;

  my $hypid = 1;
  my @outstrings;
  while (@lines) {
    my ($conf) = shift @lines;
    my @feats = "conf=$conf";
    if ($conf eq '-0') {
      push @feats, "parsefail=1";
    } elsif ($conf eq '0') {
      push @feats, "nowords=1";
    }

    my ($tree) = shift @lines;
    $tree =~ s/^\s*\(S1 (.*)\)\s*$/$1/;  # fix Eugene C's quirky top node

    push @outstrings, "# $id.h$hypid @feats";

    use Lingua::Treebank;
    my $constituent_tree =
      Lingua::Treebank::Const->new()->from_penn_string($tree);
    $headfinder->annotate_heads($constituent_tree);

    if ($DEBUG) {
      warn "tree $id.h$hypid conf=$conf\n";
      warn $constituent_tree->as_penn_text() . "\n";
      warn "hit a key to continue\n";
      my $input = <STDIN>;
    }

    push @outstrings, $class->strings_from_headed_tree($constituent_tree), "";

    ++$hypid;
  }

  return join "\n", @outstrings;
}

sub strings_from_headed_tree {
  my $class = shift;
  my $tree = shift;
  my @words = $tree->get_all_terminals;

  my %word2index;
  for (0 .. $#words) {
    my $word = $words[$_];
    if ($word2index{$word + 0}) { # use hex address
      warn "doubly-defined word?"
    }
    $word2index{$word + 0} = ($_ + 1);
  }

  my @outstrings;
  for my $word (@words) {
    my %feats;
    $feats{wdindex} = $word2index{$word + 0};
    $feats{word} = $word->word();
    $feats{lemma} = '_'; # give up
    $feats{cpos} = $word->tag(); # could coarsen
    $feats{pos} = $word->tag();

    my $max_proj = $word->maximal_projection();
    my $governing_phrase = $max_proj->parent();

    if ($max_proj->is_root()) {
      $feats{head} = 0;
      $feats{modtype} = "ROOT/" . $max_proj->tag();
    }
    else {
      my $governing_word = $governing_phrase->headterminal();
      $feats{head} =
	$word2index{$governing_word + 0};
      $feats{modtype} =
	join "/", $governing_phrase->tag(), $max_proj->tag();
    }

    $feats{projhead} = '_';
    $feats{feats} = '_';
    $feats{projmodtype} = '_';

    my @feats_out;
    for my $featname ( qw( wdindex word lemma cpos pos),
		       qw( feats head modtype projhead projmodtype ) ) {
      warn "feat $featname undefined"
	unless defined $feats{$featname};
      push @feats_out, $feats{$featname};
    }
    push @outstrings, join ("\t", @feats_out);

  }

  return @outstrings;
}
##################################################################
package DepWord;
use strict;
use warnings;
use Carp;

sub new {
  my $class = shift;
  my %args = @_;
  my $self = bless \%args, $class;
  return $self;
}

sub from_text {
  my $class = shift;
  my $text = shift;
  # see http://nextens.uvt.nl/depparse-wiki/DataFormat
  my %dep;
  @dep{'wdindex', 'word', 'lemma',
	 'cpos', 'pos', 'feats',
	   'head', 'modtype',
	     'projhead', 'projmodtype'} = split " ", $text;

  my $self = $class->new(%dep);

  return $self;
}

##################################################################
package Dep::Forest;

use SentList;
our @ISA = 'Line';  # from SentList
use strict;
use warnings;
use Carp;

sub new {
  my $class = shift;
  my %args = @_;
  return bless \%args, $class;
}

sub list_spelled {
  my $self = shift;
  my $component = shift;
  my %args = @_;

  my $class = ref $self;

  my @trees = @{$self->{forest}};
  shift @trees;  # discard 0 (1-based)

  if (not defined $args{parse_nbest}) {
    croak "no parse_nbest handed to $class";
  }
  if ($args{parse_nbest} < 1) {
    carp "parse_nbest has value < 1";
    $args{parse_nbest} = 1;
  }
  if (not defined $args{parse_gamma}) {
    carp "no parse_gamma defined, setting to 1";
    $args{parse_gamma} = 1;
  }


  # prune the list down
  use List::Util 'min';
  $#trees = min($#trees, $args{parse_nbest} - 1);

  if (@trees == 1) {
    # if there's only one tree, it gets prob. 1 by default. Thus
    # assigning 0 logprob to (single) null tree won't break this.
    return $trees[0]->list_spelled($component, %args);
  }


  my %sum;
  my $totalweight =
    Parse->logsum( map {$_->confidence($args{parse_gamma})} @trees );

  for my $tree (@trees) {
    my %tree_ct = $tree->list_spelled($component, %args);

    # input confidences are in log space.
    # in non-log space, w = p(x_i) / (sum_j p(x_j))
    # in log space, log(w) = log (x_i) - log( sum_j p(x_j))

    my $logweight = $tree->confidence($args{parse_gamma}) - $totalweight;

    for (keys %tree_ct) {
      # expected count: count times weight.
      # expected count in log space: log-count + log-weight
      my $log_e_ct = Parse->to_log($tree_ct{$_}) + $logweight;

      if (defined $sum{$_}) {
	$sum{$_} = Parse->logsum($sum{$_}, $log_e_ct);
      }
      else {
	$sum{$_} = $log_e_ct;
      }
    }
  }

  # convert from log space:
  my %out;
  for (keys %sum) {
    my $logval = $sum{$_};
    my $realval = Parse->from_log($logval);
    next if ($realval < $class->threshold);

    $out{$_} = $realval;
  }
  return %out;
}

sub trees {
  my $self = shift;
  return map {$self->{forest}[$_]} (1 .. $#{$self->{forest}});
}

sub threshold {
  my $class = shift;
  return '0.00001';  #that oughtta do it
}

sub addhyp {
  my $self = shift;
  my %args = @_;

  my $hypid = $args{hyp};
  my $tree = $args{deptree};

  carp "huh, looks like the deptree arg to addhyp wasn't a Deps"
    unless UNIVERSAL::isa($tree, 'Deps');

  carp "unexpectedly found two hypid $hypid of id ", $self->id
    if defined $self->{forest}[$hypid];

  $self->{forest}[$hypid] = $tree;
}

sub id {
  my $self = shift;
  return $self->{id};
}

1;
