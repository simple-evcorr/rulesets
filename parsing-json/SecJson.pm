package SecJson;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our $VERSION = 1.00;
our @EXPORT_OK = qw(json2matchvar);

# this module needs the perl JSON module for parsing json input

use JSON;

sub flatten {  
  my($ref, $ret, $prefix) = @_;
  my($key, $i); 

  if (ref($ref) eq "HASH") {  

    foreach $key (keys %{$ref}) {  
      if (ref($ref->{$key}) eq "") {  
        $ret->{$prefix . $key} = $ref->{$key};  
      } elsif (ref($ref->{$key}) eq "HASH") {  
        flatten($ref->{$key}, $ret, $prefix . $key . "!");  
      } elsif (ref($ref->{$key}) eq "ARRAY") { 
        flatten($ref->{$key}, $ret, $prefix . $key . "!");  
      } else {  
        $ret->{$prefix . $key} = ${$ref->{$key}};  
      }  
    }  

  } elsif (ref($ref) eq "ARRAY") {  

    for ($i = 0; $i < scalar( @{$ref}); ++$i) {  
      if (ref($ref->[$i]) eq "") {  
        $ret->{$prefix . $i} = $ref->[$i];  
      } elsif (ref($ref->[$i]) eq "HASH") {  
        flatten($ref->[$i], $ret, $prefix . $i . "!");  
      } elsif (ref($ref->[$i]) eq "ARRAY") {  
        flatten($ref->[$i], $ret, $prefix . $i . "!");  
      } else {  
        $ret->{$prefix . $i} = ${$ref->[$i]};  
      }  
    }  

  }  
}  

# This function expects a valid JSON string for its first parameter,
# while the second parameter is an optional variable prefix (if not
# given, it defaults to "").
# The function parses the JSON string, stores the parsing results into
# a perl hash, and returns a reference to the hash. This reference can
# be returned from the sec PerlFunc pattern, in order to initialize sec 
# match variables in sec rules.
# For example, if the following JSON string is submitted to the function:
#
# {"test1":"my string","test2":[9.2,{"test3":"abc","test4":{"test5":12.7}}]}
#
# the function converts this JSON string to a hash table with the following
# keys and values:
#
# test1 => my string
# test2!0 => 9.2
# test2!1!test3 => abc
# test2!1!test4!test5 => 12.7
#
# If a reference to this hash table is returned from the sec PerlFunc
# pattern, the following match variables become visible to sec:
#
# $+{test1} = my string
# $+{test2!0} = 9.2
# $+{test2!1!test3} = abc
# $+{test2!1!test4!test5} = 12.7 
#
# If the prefix (the second function parameter) is given, all variable
# names are prefixed with it. For example, setting the prefix to "json!"
# would create the match variable $+{json!test1} with the value "my string"
# for the above example JSON input string.
#
# Note that in order to create a sec match variable from a JSON field,
# the field name must follow the naming convention of sec match variable:
# (a) digits only (e.g., $1) 
# (b) the first character is a letter or underscore, while the following
#     characters can be alphanumerals, underscores and exclamation marks
#     (e.g., $+{_inputsrc} or $+{myvar})

sub json2matchvar {
  my($json_line, $prefix) = @_;
  my($ptr, $matchvar_hash); 

  if (!defined($json_line)) { return; }
  if (!defined($prefix)) { $prefix = ""; }

  $ptr = JSON::decode_json($json_line);
  $matchvar_hash = {};

  flatten($ptr, $matchvar_hash, $prefix); 

  return $matchvar_hash;
}

1;

