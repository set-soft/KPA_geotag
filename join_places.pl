#!/usr/bin/perl
# Author:  Salvador E. Tropea
# License: Public Domain
# Objetive: Joins two places to coordinates files.
#           The first is the reference, the seconds contains extra coordinates
# Input files: List of places to populate, reference (gps_places.txt)
#              List of places with coordinates, subset of the first (segovia_gps.txt)
# Output file: List of places, the reference enhanced by the second  (new_places.txt)

use strict;
use warnings;

# Parameters
# All files encoded as the default Perl encoding i.e. ISO-8859-1
my $places_db='gps_places.txt';
my $extra_db='segovia_gps.txt';
my $output_db='new_places.txt';

# Work
print "Loading GPS coordinates from `$extra_db'...\n";
open(FI,$extra_db) or die 'Failed to open '.$extra_db;
my ($l, $c);
my %gps_lat;
while ($l=<FI>)
  {
   if ($l=~/(.*)\s+(\-*[\d\.]+),(\-*[\d\.]+)/)
     {
      my ($place,$lat,$long)=($1,$2,$3);
      $place=~s/\s+$//;
      $gps_lat{$place}="$lat,$long";
      $c++;
     }
  }
close(FI);
print "  $c coordinates available\n";

print "Loading GPS coordinates from `$places_db' and writing to `$output_db'...\n";
$c=0;
my $total=0;
my $w_gps=0;
open(FI,$places_db) or die 'Failed to open '.$places_db;
open(FO,'>'.$output_db) or die 'Failed to create '.$output_db;
while ($l=<FI>)
  {
   $total++;
   if ($l=~/(.*)\s+(\-*[\d\.]+),(\-*[\d\.]+)/)
     {
      print FO $l;
      $w_gps++;
     }
   else
     {
      $l=~s/\s+$//;
      my $coord=$gps_lat{$l};
      if ($coord)
        {
         print FO "$l $coord\n";
         $c++;
         $w_gps++;
        }
      else
        {
         print FO "$l\n";
        }
     }
  }
close(FO);
close(FI);
print "  $c coordinates added\n";
printf("  $w_gps out of $total with GPS coords (%5.2f%%)\n",$w_gps/$total*100);
0;

