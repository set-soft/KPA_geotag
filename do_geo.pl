#!/usr/bin/perl
# Author:  Salvador E. Tropea
# License: Public Domain
# Objetive: Tries to figure out the GPS coordinates for a list of places
# Input files: List of places (input.txt)
# Output file: List of places with suggested coordinates (output.txt)
#
# YOU NEED AN OPENCAGE KEY!!!

use Geo::Coder::OpenCage;

# OpenCage key (you can get one for free)
$key='................................';
# Input and output must be UTF-8 encoded
$in_db='input.txt';
$out_db='output.txt';


binmode STDOUT,':utf8';
my $Geocoder=Geo::Coder::OpenCage->new(api_key => $key);

open(FI,$in_db) or die 'Failed to open '.$in_db;
binmode FI,':utf8';
open(FO,'>'.$out_db) or die 'Failed to create '.$out_db;
binmode FO,':utf8';
my ($l,$c);
my %gps_lat;
while ($l=<FI>)
  {
   print FO $l;
   FO->flush();
   print $l;
   if ($l=~/(.*)\s+(\-*[\d\.]+),(\-*[\d\.]+)/)
     {
      my ($place,$lat,$long)=($1,$2,$3);
      #print "$place $lat,$long\n";
      $gps_lat{$place}="$lat,$long";
      $c++;
     }
   else
     {# Get the data from OpenCage
      my $result=$Geocoder->geocode(location => $l, language => "es", countrycode => "es");
      my $n=$result->{total_results};
      my $i;
      for ($i=0; $i<$n; $i++)
         {
          my $r=$result->{results}[$i];
          print FO "  ".$r->{formatted}."     ".$r->{geometry}->{lat}.",".$r->{geometry}->{lng}."\n";
         }
      sleep(1);
     }
  }
exit(0);

