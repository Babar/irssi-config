#!/usr/bin/perl -w

use strict;
my ($n,$r,$line,$name, %h)=(0,0,0);
my $file = shift || "ho_reformat.data";

open(IN, $file) or die "Can't open file $file";
while(<IN>) {
  chomp;
  next if /^$/ or /^#.*$/;
  if ($n==0 && /^([a-zA-Z_0-9]+)($| continuematching$)/) {
    $n++;
    $name=$1;
    $line=$.;
  } elsif ($n==3 && /^(\S+)($| (HILIGHT|MSG)$)/) {
    $r++;
    $n=0;
    print "WARNING: line $.: $name already defined line $h{$name}\n" if defined $h{$name};
    $h{$name}=$line;
  } else {
    $n++;
  }
}
close(IN);
