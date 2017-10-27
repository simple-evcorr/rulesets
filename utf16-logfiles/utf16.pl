#!/usr/bin/perl -w

use POSIX qw(:errno_h SEEK_CUR SEEK_SET);
use Encode;
use Encode::Unicode;

if (scalar(@ARGV) < 2) {

print STDERR << "USAGEINFO";

Usage: $0 <infile> <outfile> <mode> <encoding>

tail <infile> that contains UTF16 data and output incoming lines 
to <outfile> in UTF8 format. If - (dash) is provided for <outfile>,
UTF8 lines are written to standard output. On HUP signal, <outfile>
will be reopened.

<mode> - set to either all or new
all - before switching to tail mode, print all lines in <infile> 
new - switch to tail mode immediately (default)

<encoding> - encoding for <infile>: UTF-16LE (default), UTF-16BE or UTF16

USAGEINFO

exit(0);
}

$infile = $ARGV[0];
$outfile = $ARGV[1];

if (!defined($ARGV[2])) { 
  $new = 1; 
} elsif ($ARGV[2] eq "new") {
  $new = 1;
} elsif ($ARGV[2] eq "all") {
  $new = 0;
} else {
  die "mode has to be set to 'all' or 'new'\n";
}

if (!defined($ARGV[3])) { 
  $encoding = "UTF-16LE"; 
} elsif ($ARGV[3] =~ /^(UTF-16(?:LE|BE)?)/i) {
  $encoding = $1;
} else {
  die "encoding has to be set to 'UTF-16LE', 'UTF-16BE' or 'UTF-16'\n";
}

##################################################

sub open_input {
  while (!open(INFILE, $infile)) {
    if ($! == EINTR) { next; }
    die ("Can't open $infile: $!\n");
  }
}

sub open_output {
  if ($outfile eq "-") {
    while (!open(OUTFILE, ">&STDOUT")) {
      if ($! == EINTR) { next; }
      die "Can't dup standard output: $!\n";
    }
    binmode(OUTFILE, ":utf8");
  } else {
    while (!open(OUTFILE, ">>:utf8", $outfile)) {
      if ($! == EINTR) { next; }
      die ("Can't open $outfile: $!\n");
    }
  }
  select OUTFILE;
  $| = 1;
  select STDOUT;
}

##################################################

$WIN32 = ($^O =~ /win/i  &&  $^O !~ /cygwin/i  &&  $^O !~ /darwin/i);

# encode newline in UTF16, and if BOM marker gets added, drop it

$newline = encode($encoding, "\n");
if (length($newline) == 4) { substr($newline, 0, 2) = ""; }
if (length($newline) != 2) { die "Failed to encode newline\n"; }

$data = "";
$hup_received = 0;

$SIG{HUP} = sub { $hup_received = 1; };

open_input();

if ($new) {
  $offset = (stat(INFILE))[7];
  if ($offset & 1) { --$offset; }
  for (;;) {
    $fpos = sysseek(INFILE, $offset, SEEK_SET);
    if (defined($fpos)) { last; }
    if ($! == EINTR) { next; }
    die "Can't seek $infile: $!\n";
  }
}

open_output();

for (;;) {

  if ($hup_received) {
    print STDERR "reopening $outfile\n";
    close(OUTFILE);
    open_output();
    $hup_received = 0;
  }

  $n = sysread(INFILE, $buffer, 8192);

  if (!defined($n)) {

    if ($! == EINTR) { next; }
    die ("IO error when reading from $infile: $!\n");

  } elsif ($n == 0) { 

    @stat = stat($infile);
    @stat2 = stat(INFILE);

    if (!scalar(@stat)) {
      sleep(1);
      next;
    }

    if (!$WIN32) {
      if ($stat[0] != $stat2[0] || $stat[1] != $stat2[1]) {
        print STDERR "$infile rotated\n";
        close(INFILE);
        open_input();
        next;
      }
    }

    for (;;) {
      $fpos = sysseek(INFILE, 0, SEEK_CUR);
      if (defined($fpos)) { last; }
      if ($! == EINTR) { next; }
      die "Can't seek $infile: $!\n";
    }

    if ($fpos > $stat[7]) { 
      print STDERR "$infile truncated\n";
      close(INFILE);
      open_input();
      next;
    }

    sleep(1);
    next;
  }

  $data .= $buffer;

  for (;;) {

    $pos2 = 0;

    for (;;) {
      $pos = index($data, $newline, $pos2);
      if ($pos == -1) { 
        $newline_found = 0; 
        last; 
      }
      if ($pos & 1) { 
        $pos2 = $pos + 2; 
      } else { 
        $newline_found = 1; 
        last; 
      }
    }
    
    if (!$newline_found) { last; }

    $line = substr($data, 0, $pos + 2, "");
    $string = decode($encoding, $line);

    print OUTFILE $string; 

  }

}
