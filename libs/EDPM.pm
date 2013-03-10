package EDPM;
use strict;
use warnings;

use DPM;
DPM->register_variant(name => 'EDPM',
			components => [ qw( 1-gram 2-gram word-arc arc-word ) ],
			nbest => 50,
			gamma => 0.25,
			monobin => 1);

1;
