package Parse;
use strict;
use warnings;
use Carp;

use ScoreConfig;

our $DEBUG = 0;
our $VERBOSE = 0;
use constant PARSE_FAIL => "-0";

our $TREE_SUFFIX = ".$ScoreConfig::PARSER_NBEST-best.trees";
if ($ScoreConfig::COMPRESS_SYNTAX_CACHE) {
  $TREE_SUFFIX .= ".gz";
}

sub syntax_treefile {
  # given a raw file, tell me where to put the Charniak trees
  my $class = shift;
  my $rawfile = shift;
  confess "syntax_treefile given undef rawfile"
    unless defined $rawfile;
  use File::Basename 'fileparse';
  my ($stem, $dir, $suffix) = fileparse($rawfile, @ScoreConfig::RAW_SUFFIXES);
  my $out = File::Spec->catfile($dir, "$stem$TREE_SUFFIX");
  warn "treefile: $out\n"
    if $VERBOSE;
  return $out;
}

sub parse_raw {
  my $class = shift;
  my $in_raw = shift;
  my $out_trees = shift;
  my %args = @_;

  use File::Temp;
  my $wordsfile = File::Temp->new( CLEANUP =>  (not $DEBUG) );
  my $treesfile = File::Temp->new( CLEANUP =>  (not $DEBUG) );

  use SentList;
  my $in_list = SentList::Text->new_from_file(file => $in_raw, %args);

  # write out a words file with all the blank lines and skips omitted
  for my $line ($in_list->nonblank_lines()) {
    if ($args{skips}{Parse}{$line->id()}) {
      carp "skipping line ", $line->id(),
	" because it was in the skips table as Parse";
      next;
    }
    my $text = $class->prep_text_for_parser($line->text());

    print $wordsfile "<s ", $line->id(), "> ", $text, " </s>\n";
  }

  # run the parser
  $class->run_parser($wordsfile, $treesfile);

  # step through the original lines, emitting dummy trees for the ones
  # we've skipped

  my @lines = $in_list->lines();
  open my $outfh, ">", $out_trees
    or die "can't open '$out_trees': $!\n";

  binmode $outfh, ":gzip" if $ScoreConfig::COMPRESS_SYNTAX_CACHE;
  {
    local $/ = "\n\n";
    while (my $line = shift @lines) {
      if ($line->is_blank()) {
	$class->write_skip($outfh,
			   id => $line->id(),
			   text => $line->text(),
			   blank => 1,
			  );
	next;
      }
      elsif ($args{skips}{Parse}{$line->id()}) {
	$class->write_skip($outfh,
			   id => $line->id(),
			   text => $line->text(),
			   prob => PARSE_FAIL,
			   parsefail => 1,
			  );
	next;
      }

      # otherwise consume another tree from parser output
      my $trees = <$treesfile>;
      if (!$ScoreConfig::VITERBI_PARSE) {
        if ($ScoreConfig::PARSER_NBEST == 1) {
          # we requested 2 trees here, but really we just want the first one
          my @treeElements = split("\n", $trees);
          $treeElements[0] =~ s/^2/1/;
          print $outfh $treeElements[0] . "\n" . $treeElements[1] . "\n" . 
                $treeElements[2] . "\n\n";
        } else {
          # we print whatever we requested in this case
          print $outfh $trees;
        }
      } else {
        #print STDERR "got <$trees>";
        # in this case, we print what was given to us - which will most likely
        # be a single parse with no probability score or header.
        print $outfh $trees; 
      }
    }
  }
}

sub prep_text_for_parser {
  my $class = shift;
  my $text = shift;
  $text =~ s/\(/ -LRB- /g;
  $text =~ s/\)/ -RRB- /g;

  # don't know if this one's needed
  $text =~ s/ \@-\@ /-/;
  return $text;
}
sub run_parser {
  my $class = shift;
  my $wordsfile = shift;
  my $treesfile = shift;
  
  if ($ScoreConfig::VITERBI_PARSE && $ScoreConfig::PARSER_NBEST != 1) {
    warn "inconsistent configuration settings: " .
         "ScoreConfig::VITERBI_PARSE = " . $ScoreConfig::VITERBI_PARSE . ", " .
         "ScoreConfig::PARSER_NBEST = " . $ScoreConfig::PARSER_NBEST;
  }

  my @args = ($ScoreConfig::PARSER,
	      "-C", '-l' . $ScoreConfig::MAX_PARSE_SENTLEN,
	      "-T" . $ScoreConfig::PARSER_BEAM,
	      ($ScoreConfig::PRETOKENIZED_RAW ? '-K' : ()),
	      '-N' . (!$ScoreConfig::VITERBI_PARSE ? 
                      ($ScoreConfig::PARSER_NBEST == 1 ? 2 : 
                       $ScoreConfig::PARSER_NBEST) : 1),
	      "$ScoreConfig::PARSER_PARAMDIR/");


  my $command =
    join " ", "ulimit", "-s", "unlimited", "&&",
	@args, "<", $wordsfile, ">", $treesfile;

  if ($VERBOSE) {
    warn "running parser: `@args`\n";
  }

  my $exitval = system("$command");
  if ($? == -1) {
    die "failed to execute parser $command: $!\n";
  }
  elsif ($? & 127) {
    die sprintf "child ('$command') died with signal %d, %s coredump\n",
      ($? & 127),  ($? & 128) ? 'with' : 'without';
  }
  else {
    warn (sprintf "child exited with value %d\n", $? >> 8)
      if $VERBOSE;
  }
}

sub write_skip {
  my $class = shift;
  my $outfh = shift;
  my %args = @_;
  my $skip_id = $args{id};
  my $skip_text = $class->prep_text_for_parser($args{text});
  my $prob = $args{prob} || 0;

  if ($skip_text =~ /^\s*$/) {
    $skip_text = '-null-';
  }
  print $outfh "1\t$skip_id\n";  # 1 parse, this id
  print $outfh "$prob\n";   # neg log prob == (undef) confidence dummy
                            # tree with FRAG root
  print $outfh "(S1 (FRAG ";
  if ($args{blank}) {
    print $outfh " ($_ $_)" for split " ", $skip_text;
  }
  elsif ($args{parsefail}) {
    print $outfh " (NOPARSE $_)" for split " ", $skip_text;
  }
  print $outfh "))\n";
  print $outfh "\n";  # done with this hyp
}

##################################################################
# what is the log weight of the input tree?
use constant BASE => 2;  # according to Matt Lease

sub logsum {
  my $class = shift;

  # given logp1, logp2, logp3, return log(p1+p2+p3)

  # http://en.wikipedia.org/wiki/List_of_logarithmic_identities#Summation.2Fsubtraction

  my @args = sort {$a <=> $b} @_;

  # log(x+y+z+...)
  # = log x + log(1 + exp(log y - log x) + exp(log z - log x) + ...)

  # this approach does one log and n-1 exponentiations.

  my $largest = pop @args;
  return $largest if (not @args);
  my @diffs = map {BASE**($_ - $largest)} @args;
  use List::Util 'sum';
  return $largest + $class->to_log(1 + sum @diffs);

## the following iterative approach does n-1 logs and n-1
## exponentiations; reject in favor of previous

#   while (@args > 1) {
#     my $smallest = shift @args;

#     # underflows cannot(?) be safely skipped
#     # next if BASE()**$smallest == 0;

#     my $diff = $smallest - $args[0];
#     $args[0] += $class->to_log(1 + BASE**$diff);
#   }
#   return $args[0];
}


sub to_log {
  my $class = shift;
  my $val = shift;
  croak "too many args to to_log"  if @_;
  return ( log($val) / log( BASE ) );
}

sub from_log {
  my $class = shift;
  my $val = shift;
  croak "too many args to from_log" if @_;
  return BASE()**$val;
}

1;
