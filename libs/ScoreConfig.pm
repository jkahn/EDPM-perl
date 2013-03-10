package ScoreConfig;
use strict;
use warnings;

use Carp;

# for other packages. Users may modify this file to point to various
# external tools

# 'our' variables are used externally.  'my' variables here make this
# file easier to manipulate

my $ROOT="/home/jgk/work/EDPM";
# my $ROOT="/homes/iskander/workplace/svnTree/EDPM/trunk";
# my $ROOT="/homes/jgk/parsing-mt/edpm-dist";


# Charniak distro parameters
my $PARSER_ROOT="/g/ssli/software/pkgs/charniak-parser/reranking-parserAug06/first-stage";


##### Probably no need to change parameters below here #####

our $VERBOSE = 0;

our $PARSER = "$PARSER_ROOT/PARSE/parseIt";
our $PARSER_PARAMDIR = "$PARSER_ROOT/DATA/EN";

our $TERCOM_PERL = "$ROOT/scripts/tercom_v6b.pl";

our $MAX_NGRAM = 9;  #don't store ngram stats larger than 9-grams.

our $BLEU_EPSILON = 0.001;  # when 0 hypothesized, precision is 0.001 to
                            # avoid zeros

our $MAX_PARSE_SENTLEN = 200;
our $PARSER_BEAM = 210;

our $PARSER_NBEST = 50;

our $VITERBI_PARSE = 0; # boolean variable

our @RAW_SUFFIXES = '.raw';

our $DATADIR = "$ROOT/data";


our $COMPRESS_SYNTAX_CACHE = 1;  # we'll need PerlIO::gzip

our $PRETOKENIZED_RAW = 0;  # 0=un-pretokenized


1;
