#!/usr/bin/perl
# Author:  Salvador E. Tropea
# License: Public Domain
# Objetive: Fill the EXIF DB GPS coords using the "Places" category.
# Input files: XML Database (index.xml)
#              Places to coordinates table (gps_places.txt)
#              EXIF database (exif-info.db)
# Output file: EXIF database (exif-info.db)

use DBI;
use strict;
use warnings;
use XML::LibXML;

# Relative to the index.xml
# Files from the XML will get this as prefix
my $prefix='/home/salvador/Fotos/';
# XML database
my $filename='index.xml';
# Text file with the coordinates for the "Places" in the XML
# Format: (encoded as the default Perl encoding i.e. ISO-8859-1)
# Place    Latitude,Longitude
my $gps_places='gps_places.txt';
#my $gps_places='gps_fix.txt';
# A special place to be ignored
my %sin_lugar=
   (
    "Sin lugar" => 1,
    "Desconocido" => 1,
    "Mc Donald's Desconocido" => 1,
   );
# Overwrite GPS coords, DANGEROUS!!!
my $force=0;
# To suppress the warnings
my $print_warnings=1;

# Read our "places" database
print "Loading GPS coordinates ...\n";
open(FI,$gps_places) or die 'Failed to open '.$gps_places;
my ($l, $c, $ct, $sup_warn);
my %gps_lat;
$sup_warn=0;
while ($l=<FI>)
  {
   $ct++;
   if ($l=~/(.*)\s+(\-*[\d\.]+),(\-*[\d\.]+)/)
     {
      my ($place,$lat,$long)=($1,$2,$3);
      #print "$place $lat,$long\n";
      $place=~s/\s+$//;
      $gps_lat{$place}="$lat,$long";
      $c++;
     }
   else
     {
      chomp $l;
      Warning($l,'without GPS coords');
     }
  }
close(FI);

print "  $c/$ct coordinates available\n";

print "Opening EXIF database ...\n";
my $driver="SQLite";
my $database="exif-info.db";
my $dsn="DBI:$driver:dbname=$database";
my $userid="";
my $password="";
my $dbh=DBI->connect($dsn,$userid,$password,{ RaiseError => 1 })
        or die $DBI::errstr;
print "  EXIF database opened\n";


print "Reading XML database ...\n";
my $dom=XML::LibXML->load_xml(location => $filename);
my ($no_upd, $upd, $no_place);
my ($ind,$total);
$upd=0;
$ind=0;
my @images=$dom->findnodes('/KPhotoAlbum/images/image');
$total=scalar(@images);
foreach my $image (@images)
   {
    my $lgs=0;
    my $file=$image->getAttribute('file');
    $ind++;
    if ($ind%100==0)
      {
       print "$ind/$total       \r";
       select()->flush();
      }
    if (HaveGPS($file) and !$force)
      {
       $no_upd++;
      }
    else
      {
       my ($plf, $skip_place);
       foreach my $opt ($image->findnodes('./options/option'))
          {
           my $attr=$opt->getAttribute('name');
           if ($attr eq 'Places')
             {
              foreach my $pl ($opt->findnodes('./value'))
                 {
                  my $place=$pl->getAttribute('value');
                  unless ($sin_lugar{$place})
                    {
                     $plf=$place;
                     last;
                    }
                  $skip_place=1;
                 }
              last;
             }
          }
       if ($plf)
         {
          my $co=$gps_lat{$plf};
          if ($co)
            {
             my ($lat,$lon)=split(/,/,$co);
             $upd++ if SetGPS($file,$lat,$lon);
            }
          else
            {
             Warning($plf,'without GPS coords');
            }
         }
       else
         {
          if ($skip_place)
            {
             $no_place++;
            }
          else
            {
             Warning($file,'without `Place\'');
             $no_upd++;
            }
         }
      }
   }
print "$ind/$total\n";
print "With GPS (not updated): $no_upd\n";
print "Placed GPS coords: $upd\n";
print "Intentionally skipped: $no_place\n";
printf("Currently geotagged: %5.2f%%\n",(($no_upd+$upd+$no_place)/$total*100));

$dbh->disconnect();
print "  EXIF database closed\n";

print "$sup_warn warnings suppressed\n" if $sup_warn;
0;

sub SetGPS
{
 my ($file,$lat,$long)=@_;
 my $f=$prefix.$file;
 my $la=abs($lat);
 my $lar='N';
 $lar='S' if $lat<0;
 my $lo=abs($long);
 my $lor='E';
 $lor='W' if $long<0;
 my $stmt="UPDATE exif set ".
          "Exif_GPSInfo_GPSVersionID=0, ".
          "Exif_GPSInfo_GPSAltitude=0.0, ".
          "Exif_GPSInfo_GPSAltitudeRef=0, ".
          "Exif_GPSInfo_GPSMeasureMode='', ".
          "Exif_GPSInfo_GPSDOP=-1.0, ".
          "Exif_GPSInfo_GPSImgDirection=-1.0, ".
          "Exif_GPSInfo_GPSLatitude=$la, ".
          "Exif_GPSInfo_GPSLatitudeRef='$lar', ".
          "Exif_GPSInfo_GPSLongitude=$lo, ".
          "Exif_GPSInfo_GPSLongitudeRef='$lor', ".
          "Exif_GPSInfo_GPSTimeStamp=-1.0 ".
          "where filename='$f';";
 #print "$stmt\n";
 my $rv=$dbh->do($stmt) or die $DBI::errstr;

 die "rv<0 ".$DBI::errstr if $rv<0;
 die "rv>1 for $file" if $rv>1;
 print "Warning: $file not in EXIF database\n" if ($rv!=1 and $file=~/jpg$/i);
 return $rv==1;
}

sub HaveGPS
{
 my ($file)=@_;
 my $f=$prefix.$file;
 my $stmt="SELECT Exif_GPSInfo_GPSLatitude ".
                 "from exif ".
                 "where filename='$f';";
 my $sth=$dbh->prepare($stmt);
 my $rv=$sth->execute() or die $DBI::errstr;
 my @row=$sth->fetchrow_array();
 return ($row[0] and $row[0]>0);
}

sub Warning
{
 print 'Warning: `'.$_[0]."' ".$_[1]."\n" if $print_warnings;
 $sup_warn++ unless $print_warnings;
}

