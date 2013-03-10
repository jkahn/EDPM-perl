EDPM distribution

Author: Jeremy G. Kahn <jgk@ssli.ee.washington.edu>

INSTALLATION:

unzip this distribution to $EDPMROOT (wherever you want that to be).

INSTALLATION OF PARSER

You will need the Charniak parser installed, as well as a
trained-parameter directory (the default version ships with one). It
is tested using the first-stage parser from the August 2006
distribution which (at the time of distibution) is at: 

  ftp://ftp.cs.brown.edu/pub/nlparser/reranking-parserAug06.tar.gz

unzip this to $PARSER.

CONFIGURATION

You will need to change some values in $EDPMROOT/libs/ScoreConfig.pm .
You need to change ROOT to point to $EDPMROOT and $PARSER_ROOT to
point to $PARSER/first-stage .

PERL PREREQUISITES:

Perl 5.8  (5.8.8 at least, if you can. 5.8.6 will probably work.)

You probably want to install the PerlIO::gzip module if it is not
already there (to save hugely on cache space).  If you do not have it,
set $COMPRESS_SYNTAX_CACHE to zero in ScoreConfig.pm.

RUNNING THE CODE

This is a system of Perl libraries. no installation should be required
beyond the above. The code in $EDPMROOT/scripts expects to find those
libraries in $EDPMROOT/libs -- any other code you write to access
these libraries will need to have $EDPMROOT/libs available in the
module paths.

The critical functionality can be accessed through scripts as follows:

  > $EDPMROOT/scripts/scores-from-raw --translation $TRANSFILE \
     --reference $REFFILE

CACHEFILE CREATION

The core code does basic timestamp checking and will not regenerate a
tree or dependency file if the target file exists and is newer than
the source. 

.trees.gz and .deps.gz files will be generated alongside $TRANSFILE
and $REFFILE (which must both end in .raw under normal use).  Score
cachefiles will be generated alongside $TRANSFILE (see LIBRARY METHODS
below).

Scoring does *more* computation on the dependency trees, comparing
hypothesized to reference, and this information is what's cached in
the score cachefiles.

CREATING ONLY THE CACHE

The parsing process is slow and often needs to be broken across
multiple nodes (in a cluster, for example).  This part may be done
separately (the timestamp checking will skip it when the scoring
scripts are invoked):

  > $EDPMROOT/scripts/cache-syntax $TRANSFILE $REFFILE ...

or, more realistically,

  > for f in $TRANSFILE $REFFILE $TRANSFILE2 ... ; do \
      condor-launch $EDPMROOT/scripts/cache-syntax $f; done

Each cache-syntax process will start a separate parser and cache the
tree and dependency results. (The last cachefile -- the score
cachefile -- is generated only by the score-from-raw scripts.)

LIBRARY METHODS

In a Perl script, you can manipulate the cached scores directly by
using the methods available to the EDPM library:

  use lib 'libs';  # load the edpm-dist directory of libraries
  use EDPM;

  my $cache =
     EDPM->compute_cachename(trans => $TRANSFILE,
                             refs => [ $REFFILE ],);
  # or just get $cache yourself, it's not hard.

  my @seg_scores = EDPM->read_cachefile(cache => $cache);

  for my $seg (@seg_scores) {
    print $seg->id(), " ", $seg->score(), "\n";
  }
  my $doc_score = EDPM->combine(@seg_scores);
  print "total score from cache $cache: ", $doc_score->score(), "\n";

The script above reads a single cachefile and computes both
segment-level and document-level scores. 


CAVEATS

The system is slow: parsing takes a long time, and parser start-up is
time-expensive, so as many sentences as possible should be handed to
each instantiation of the parser.  Condor and grid-ish engines may
want to experiment with the number of sentences in each .raw file.

Wrapper scripts beyond the ones mentioned above are needed.  I expect
that they will be easy to write -- the libraries provide a very
powerful interface to the scores -- but feedback from potential users
would help me.

Parser failure: when the parser fails to come up with a parse, there
is no problem -- it generates a flat (null) parse. The problem emerges
if the parser hangs (or gets stuck thrashing). At the moment, the
system has no timer or other escape for this problem.


