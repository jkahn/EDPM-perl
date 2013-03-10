package DPM;
use strict;
use warnings;

use Carp;

use base 'ScoreXF';
use ScoreConfig;
use NGram;

use constant PARANOID => 0;
our $VERBOSE = 0;
our $HFSTEM = 'ptb-sem';

sub list_cacheable_components {
  my $class = shift;
  return ($class->list_syntax_cacheable_components,
	  $class->list_ngram_cacheable_components);
}
sub list_syntax_cacheable_components {
  my $class = shift;
  return qw( word-arc word-word word-arc-word arc-word );
}
sub list_ngram_cacheable_components {
  my $class = shift;
  return map { "$_-gram" } 1 .. $ScoreConfig::MAX_NGRAM;
}

# uses Score::write_cachefile
# uses Score::read_cachefile

# uses ScoreXF::from_cache_string
# uses ScoreXF::to_cache_string

our @CLASSES; # list of registered subclasses

sub get_name {
  # generate default name for variant 
  my $class = shift;
  my %args = @_;

  my @items = 'DPM';

  if ($args{nbest} == 1) {
    push @items, 'viterbi';
  }
  else {
    my $nbest = sprintf "%02d", $args{nbest};
    push @items, $nbest ."nbest";

    my $gammatext = sprintf "%.2f", $args{gamma};
    $gammatext =~ s/\./_/;
    push @items, $gammatext . "gamma";
  }

  if (@{$args{components}} > 1) {
    if ($args{monobin}) {
      push @items, 'mono_bin';
    }
    else {
      push @items, 'multibin';
    }
  }

  my @comp_abbrs;
  for my $component (@{$args{components}}) {
    my @words = split /-/, $component;
    s/^(.).*$/$1/ for @words;
    push @comp_abbrs, join "", @words;
  }
  push @items, join "_", @comp_abbrs;

  return join '::', @items;
}

sub register_variant {
  my $class = shift;
  my %args = @_;

  if (not defined $args{nbest}) {
    croak "no nbest defined to $class->register_variant()";
  }

  my $code = "package $args{name};\n";
  $code .= "our \@ISA = '$class';\n";
  $code .= "sub list_components { qw( @{$args{components}} ) }\n";
  $code .= "sub parse_nbest { $args{nbest} }\n";
  $code .= "sub parse_gamma { $args{gamma} }\n";
  if ($args{monobin}) {
    $code .= "sub score { my \$s = shift; \$s->score_monobin(\@_) }\n";
  }
  else {
    $code .= "sub score { my \$s = shift; \$s->score_multibin(\@_) }\n";
  }
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

sub objects_from_raw_files {
  my $class = shift;
  my %args = @_;

  my $out = $args{cache};

  my $translation = $args{trans};
  my @references = @{$args{ref}};

  delete $args{trans};
  delete $args{ref};

  $args{parse_nbest} = 1
    unless defined $args{parse_nbest};

  croak "no references given"
    unless @references;

  croak "reference is undefined"
    if grep {not defined $_} @references;

  # set up for syntax:
  my $trans_forestlist =
    $class->compute_syntax($translation,
			   hyplist => 1,
			   %args);  #other arguments


  croak "reference is undefined"
    if grep {not defined $_} @references;

  my @ref_forestlists;
  for my $ref (@references) {
    push @ref_forestlists, $class->compute_syntax($ref, hyplist => 0, %args)
  }

  # set up for ngram counts (fast)
  my $trans_rawlist =
    SentList::Text->new_from_file(hyplist => 1, file => $translation);
  my @refrawlists =
    map { SentList::Text->new_from_file(hyplist => 0, file => $_) }
      @references;

  my @scores;
  for my $id ($trans_forestlist->ids) {

    # extract syntax scorers
    my ($trans_forest) = $trans_forestlist->forests_matching_id($id);
    my @ref_forests = map { $_->forests_matching_id($id) } @ref_forestlists;
    my %syntax_scorers =
      $class->extract_syntax_scorers(trans => $trans_forest,
				     ref => \@ref_forests);
    # extract ngram scorers
    my %behavior = (normalize => 1, lowercase => 0);
    my $translation_ngram =
      NGram->new(text => $trans_rawlist->text_matching_id($id), %behavior);
    my @ref_ngrams =
      map { NGram->new(text => $_->text_matching_id($id), %behavior) }
	@refrawlists;
    my %ngram_scorers =
      $class->extract_ngram_scorers(trans => $translation_ngram,
				    ref => \@ref_ngrams);

    push @scores, $class->new(scorers => {%syntax_scorers, %ngram_scorers},
			      id => $id);
  } # end id
  return @scores;
}

sub extract_syntax_scorers {
  my $class = shift;
  my %args = @_;
  my %scoreargs =
    (  parse_gamma => $class->parse_gamma(),
       parse_nbest => $class->parse_nbest(),
    );

  my %scorers;
  for my $component ($class->list_syntax_cacheable_components()) {
    my %translation_cts = $args{trans}->list_spelled($component, %scoreargs);
    my @ref_cts =
      map { {$_->list_spelled($component, %scoreargs)} }
	@{$args{ref}};

    my $scorer =
      ScoreXF::Subscore->new(type => $component,
			     translation => \%translation_cts,
			     references => \@ref_cts);
    $scorers{$component} = $scorer;
  }
  return %scorers;
}

sub extract_ngram_scorers {
  my $class = shift;
  my %args = @_;
  my %scorers;

  my $trans = $args{trans};
  my @refs = @{$args{ref}};
  for my $n (1 .. $ScoreConfig::MAX_NGRAM) {
    my $component = "$n-gram";
    my $scorer =
      ScoreXF::Subscore->new(type => $component,
			     translation => $trans->{ngrams}[$n],
			     references => [ map {$_->{ngrams}[$n]} @refs ],
			    );
    $scorers{$component} = $scorer;
  }
  return %scorers;
}


sub suffix {
  return 'dpm';
}
sub markup {
  my $class = shift;
  my $nbest = $class->parse_nbest();
  my $gamma = sprintf "%.2f", $class->parse_gamma();
  $gamma =~ s/\./_/;
  my $markup = "-$Deps::HFSTEM.${nbest}best.${gamma}gamma";
  return $markup;
}


# defaults for DPM
sub parse_gamma {  1; }
sub parse_nbest {  1; }



sub compute_syntax {
  my $class = shift;
  my $rawfile = shift;

  my %args = @_;

  my $depsfile = $class->cache_syntax($rawfile, %args);
  carp "deleted $rawfile" unless defined $rawfile;

  return SentList::Forest->new_from_file(file => $depsfile, %args);
}
sub cache_syntax {
  my $class = shift;
  my $rawfile = shift;
  my %args = @_;

  my $treefile = Parse->syntax_treefile($rawfile, %args);

  my $depsfile = Deps->syntax_depsfile($rawfile, %args);


  # major work happens here.
  if (-f $treefile and -M $rawfile >= -M $treefile) {
    carp "skipping regeneration of $treefile: exists ",
      "and newer than raw $rawfile" if $VERBOSE;
  }
  else {
    carp "regenerating $treefile: older than $rawfile"
      if -f $treefile;
    use Parse;
    Parse->parse_raw($rawfile, $treefile, %args);
  }

  if (-f $depsfile and -M $treefile >= -M $depsfile) {
    carp "skipping regeneration of $treefile: exists ",
      "and newer than raw $rawfile" if $VERBOSE;
  }
  else {
    carp "regenerating $depsfile: older than $treefile"
      if -f $depsfile;
    use Deps;
    Deps->convert_treefile_to_depsfile($treefile, $depsfile,
				       hftable => "$ScoreConfig::DATADIR/$HFSTEM.hf",
				       %args);
  }

  return $depsfile;
}

1;

