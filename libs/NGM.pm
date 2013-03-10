package NGM;
use strict;
use warnings;
use Carp;

use base 'DPM';
our @CLASSES;

sub list_components {
  my $class = shift;
  return map { "$_-gram" } 1 .. $class->max_n;
}


sub register_variant {
  my $class = shift;
  my %args = @_;

  my $code = "package $args{name};\n";
  $code .= "our \@ISA = '$class';\n";
  $code .= "sub max_n { $args{n} }\n";
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

sub get_name {
  # generate default name for variant 
  my $class = shift;
  my %args = @_;

  if ($args{n} == 1) {
    return "bagofwords_F";
  }

  my @items = 'NGM';

  if ($args{monobin}) {
    push @items, 'mono_bin';
  }
  else {
    push @items, 'multibin';
  }

  push @items, $args{n} . "gram";

  return join '::', @items;
}

1;
