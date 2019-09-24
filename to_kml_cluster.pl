#!/usr/bin/perl
# Author:  Salvador E. Tropea
# License: Public Domain
# Objetive: Creates a KML for Google Earth using clusters of $ClusterRad radius
# Input files: XML Database (index.xml)
#              EXIF database (exif-info.db)
#              Photos from $prefix
# Output file: KML file (fotos.kml)
#              33p thumbs in $icon_prefix
#              720p previews in $imgs_prefix

use DBI;
use strict;
use warnings;
use XML::LibXML;
use Math::Trig qw(great_circle_distance deg2rad pi);

# Relative to the index.xml
# Files from the XML will get this as prefix
my $prefix='/home/salvador/Fotos/';
my $icon_prefix='/home/salvador/Fotos_Data/Thumbs/';
my $imgs_prefix='/home/salvador/Fotos_Data/720p/';
# XML database
my $filename='index.xml';
# To suppress the warnings
my $print_warnings=1;
my $kml='fotos.kml';
my $doc_name='Compilado fotos';
my $doc_desc='Mis Fotos';
my %to_exclude=
   (
    "Casa Ituzaingó" => 1
   );
my $ClusterRad=100;

my $sup_warn=0;

print "Opening EXIF database ...\n";
my $driver="SQLite";
my $database="exif-info.db";
my $dsn="DBI:$driver:dbname=$database";
my $userid="";
my $password="";
my $dbh=DBI->connect($dsn,$userid,$password,{ RaiseError => 1 })
        or die $DBI::errstr;
print "  EXIF database opened\n";

print "Creating $kml output ...\n";
open(FO,">$kml") or die "Failed to create `$kml'";
binmode FO,':utf8';
print FO "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print FO "<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n";
print FO " <Document>\n";
print FO "<name>$doc_name</name>\n";
print FO "  <description><![CDATA[$doc_desc]]></description>\n";

print "Reading XML database ...\n";
my $dom=XML::LibXML->load_xml(location => $filename);
my ($ind,$total);
my @images=$dom->findnodes('/KPhotoAlbum/images/image');
my ($lat,$long,$exported,$collected);
$total=scalar(@images);
$exported=0;
$collected=0;
my $excluded=0;
my %HoA;
foreach my $image (@images)
   {
    my $lgs=0;
    my $file=$image->getAttribute('file');
    $ind++;
    if ($ind%10==0)
      {
       print "$ind/$total       \r";
       select()->flush();
      }
    # Excluir algunas
    my $exclude=0;
    foreach my $opt ($image->findnodes('./options/option'))
       {
        my $attr=$opt->getAttribute('name');
        if ($attr eq 'Places')
          {
           foreach my $pl ($opt->findnodes('./value'))
              {
               my $place=$pl->getAttribute('value');
               if ($to_exclude{$place})
                 {
                  $exclude=1;
                  $excluded++;
                  last;
                 }
              }
           last;
          }
       }
    if (!$exclude and !$image->getAttribute('videoLength') and HaveGPS($file))
      {# Guardarla en un cluster
       my $rec={};
       my $label=$image->getAttribute('label');
       $label=$1 if !$label and $file=~/([^\/]+)$/;
       $rec->{label}=$label;
       $rec->{startDate}=$image->getAttribute('startDate');
       $rec->{endDate}=$image->getAttribute('endDate');
       $rec->{angle}=$image->getAttribute('angle');
       $rec->{desc}=Webify($image->getAttribute('description'));
       #print $rec->{desc}."\n>".$image->getAttribute('description')."<\n";
       $rec->{file}=$file;
       my $coord="$lat,$long";
       if ($HoA{$coord})
         {# Exact match
          push @{ $HoA{$coord} },$rec;
         }
       else
         {
          my $found=0;
          my @p1=GPS2Rad($lat,$long);
          foreach my $cn (keys %HoA)
             {
              my @p2=GPS2Rad(split(/,/,$cn));
              if (great_circle_distance(@p1,@p2,6371e3)<$ClusterRad)
                {# Cluster match
                 push @{ $HoA{$cn} },$rec;
                 $found=1;
                 last;
                }
             }
          # New coordinate
          $HoA{$coord}=[$rec] unless $found;
         }
       $collected++;
       #last if $collected>10;
      }
   }

print "\nCollected $collected images in ".scalar(%HoA)." clusters\n";
$ind=0;
# Volcar los clusters
my $coord;
for $coord (keys %HoA)
   {
    my $arr=$HoA{$coord};
    #print "$coord ".scalar(@$arr)."\n";
    print FO "  <Placemark>\n";
    print FO "   <name>".$$arr[0]->{label}."</name>\n";
    my ($lat,$long)=split(/,/,$coord);
    print FO "   <Point><coordinates>$long,$lat</coordinates><altitudeMode>clampToGround</altitudeMode><extrude>1</extrude></Point>\n";
    # Icon
    my $icon=$icon_prefix.$$arr[0]->{file};
    print FO "   <Style><IconStyle><Icon><href>$icon</href></Icon></IconStyle><BalloonStyle>\$[description]</BalloonStyle></Style>\n";
    unless (-e $icon)
      {
       my $path=$icon;
       $path=~s/([^\/]+)$//;
       `mkdir -p "$path"`;
       my $cmd="convert \"".$imgs_prefix.$$arr[0]->{file}."\"  -auto-orient -resize x33 -quality 85% \"$icon\"";
       system($cmd);
      }
    my ($stDate, $enDate);
    print FO "   <description>\n";
    foreach my $rec (@$arr)
       {
        $ind++;
        if ($ind%10==0)
          {
           print "$ind/$collected       \r";
           select()->flush();
          }
        #print " ".$rec->{file}."\n";
        my $file=$rec->{file};
        my $fn=$imgs_prefix.$file;
        my $desc=$rec->{desc};
        my $startDate=$rec->{startDate};
        my $endDate=$rec->{endDate};
        my $date=$startDate;
        $date=$startDate." - ".$endDate if $endDate;
        print FO "    $date<br/><a href=\"file://$prefix$file\"><img src=\"$fn\"/></a><br/>$desc<br/>\n";
        unless (-e $fn)
          {
           my $path=$fn;
           $path=~s/([^\/]+)$//;
           `mkdir -p "$path"`;
           my $cmd="convert \"$prefix$file\" -auto-orient -resize x720 -quality 85% \"$fn\"";
           system($cmd);
          }
        # Update the date range
        if ($stDate)
          {
           $stDate=$startDate if IsLessThan($startDate,$stDate);
          }
        else
          {
           $stDate=$startDate;
          }
        if ($endDate)
          {
           if ($enDate)
             {
              $enDate=$endDate if IsLessThan($enDate,$endDate);
             }
           else
             {
              $enDate=$endDate;
             }
          }
#         # OK hasta la 15000 luego hasta 20400 puede haber problema
#         #if ($angle)
#         #  {
#         #   `mogrify -rotate -$angle "$fn"`;
#         #   `mogrify -auto-orient "$fn"`;
#         #   `mogrify -rotate $angle "$icon"`;
#         #  }
        $exported++;
        #last if $exported>150;
       }
    print FO "   </description>\n";
    if ($enDate)
      {
       print FO "   <TimeStamp><begin>$stDate</begin><end>$enDate</end></TimeStamp>\n";
      }
    else
      {
       print FO "   <TimeStamp><when>$stDate</when></TimeStamp>\n";
      }
    print FO "  </Placemark>\n";
   }
print "$ind/$collected\n";

$dbh->disconnect();
print "  EXIF database closed\n";

print FO " </Document>\n";
print FO "</kml>\n";
print "Exported $exported files($excluded excluded)\n";
close(FO);

print "$sup_warn warnings suppressed\n" if $sup_warn;
0;

sub HaveGPS
{
 my ($file)=@_;
 my $f=$prefix.$file;
 my $stmt="SELECT Exif_GPSInfo_GPSLatitude, Exif_GPSInfo_GPSLatitudeRef, Exif_GPSInfo_GPSLongitude, Exif_GPSInfo_GPSLongitudeRef ".
                 "from exif ".
                 "where filename='$f';";
 my $sth=$dbh->prepare($stmt);
 my $rv=$sth->execute() or die $DBI::errstr;
 my @row=$sth->fetchrow_array();
 $lat=$row[0];
 $lat=-$lat if $row[1] eq 'S';
 $long=$row[2];
 $long=-$long if $row[3] eq 'W';
 return ($row[0] and $row[0]>0);
}

sub Warning
{
 print 'Warning: `'.$_[0]."' ".$_[1]."\n" if $print_warnings;
 $sup_warn++ unless $print_warnings;
}

sub Webify
{
 my $desc=$_[0];
 if ($desc)
   {
    $desc=~s/&/&amp;/g;
    $desc=~s/\n/<br\/>/g;
   }
 else
   {
    $desc='';
   }
 $desc;
}

# Notice the 90 - latitude: phi zero is at the North Pole.
sub GPS2Rad
{
 deg2rad($_[0]), deg2rad(90-$_[1])
}

sub IsLessThan
{
 my ($da1,$da2)=@_;
 my ($y1,$m1,$d1,$h1,$mi1,$s1);
 my ($y2,$m2,$d2,$h2,$mi2,$s2);
 $da1=~/(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/;
 ($y1,$m1,$d1,$h1,$mi1,$s1)=($1,$2,$3,$4,$5,$6);
 $da2=~/(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/;
 ($y2,$m2,$d2,$h2,$mi2,$s2)=($1,$2,$3,$4,$5,$6);
 return 1 if $y1<$y2;
 return 0 if $y1>$y2;
 return 1 if $m1<$m2;
 return 0 if $m1>$m2;
 return 1 if $d1<$d2;
 return 0 if $d1>$d2;
 return 1 if $h1<$h2;
 return 0 if $h1>$h2;
 return 1 if $mi1<$mi2;
 return 0 if $mi1>$mi2;
 return 1 if $s1<$s2;
 return 0 if $s1>$s2;
 return 0;
}

