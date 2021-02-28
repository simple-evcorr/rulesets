package SecUtf8;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our $VERSION = 1.00;
our @EXPORT_OK = qw(match);

use Encode;

use vars qw( %patterns );


sub match {

  my($line, $regexp) = @_;
  my(@matches);

  # convert UTF-8 multibyte characters in input line to Perl wide characters
  # (if input line contains characters in any other encoding like iso-8859-1 
  # which is supported by Perl Encode module, replace UTF-8 in the following
  # line, e.g., Encode::decode('iso-8859-1', $line))

  $line = Encode::decode('UTF-8', $line);

  # if the regular expression used for matching the line has not been
  # compiled yet, compile it and store in memory

  if (!exists($patterns{$regexp})) { $patterns{$regexp} = qr/$regexp/; }

  # match the input line with Perl wide characters, and store data matched 
  # by capture groups into the array @matches (since the input line contains
  # Perl wide characters, regular expressions like \w will no longer match 
  # only ASCII characters but also relevant Perl wide characters)

  @matches = ($line =~ $patterns{$regexp});

  # convert Perl wide characters in the array @matches to UTF-8 multibyte 
  # characters (if conversion into any other encoding like iso-8859-1 is 
  # required and this encoding supported by Perl Encode module, replace 
  # UTF-8 in the following line, e.g., Encode::encode('iso-8859-1', $_))

  @matches = map { Encode::encode('UTF-8', $_) } @matches;

  # return the array @matches, so that its elements would be mapped to
  # SEC match variables $1, $2, etc. (since Perl wide characters are not
  # returned from this function, it will avoid Perl warnings and errors
  # when Perl wide characters are written to outputs like files and sockets)

  return @matches;
}


1;
