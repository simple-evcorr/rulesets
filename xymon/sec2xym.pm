#ident  "@(#)sec2xym.pm"
#******************************************************************************
# $Id$
# $Revision$
# $Author$
# $Date$
# $HeadURL$
#******************************************************************************
#
# NAME
#   sec2xym.pm
#
# DESCRIPTION
# 
# This is a perl module containing subroutines that are intended exclusively
# for calling from SEC.  The provide native (eg cross platform) access to
# some specific interfaces with an upstream Xymon server.
#
# CHANGES
#
#   0.5.0 2014-03-03 First version released to other environments.
#   0.6.0 2014-03-04 API for XymonStatusUpdate modified.
#                    external unlocker script moved to ext directory.
#   0.6.1 2014-03-04 bug fix: offline copy,
#                    defensive arrangement of code wrt version.
#   0.6.2 2014-03-13 bug fix: disable alarms in sendToXymon for Win32.
#   0.6.3 2014-03-21 bug fix: handle empty log directory.
#   0.7.0 2014-10-18 XymonStatusModify added.
#   0.7.1 2014-12-07 relink_logpath added (similar to refresh_logpath but
#                    uses soft (symbolic) link and optionaly alerts on mtime.
#                    Private functions added:-
#                    mysymlink,check_val,isnumeric,setworstcolour

package Sec2Xym;
our $VERSION = '0.7.1';

use strict;
use warnings;
#no warnings;
use Cwd;
use File::Basename;
use File::Spec;
use Sys::Hostname;
use feature 'switch';   # needs perl 5.10 and later

our $SELF = 'Sec2Xym';
use base qw(Exporter);
our @EXPORT_OK = qw(init_sec2xym sendToXymon refresh_config refresh_logpath relink_logpath XymonStatusUpdate fake_signal_handler XymonStatusModify);

use POSIX qw(strftime);

# check if the platform is win32
my $WIN32 = ($^O =~ /win/i  &&  $^O !~ /cygwin/i  &&  $^O !~ /darwin/i);

my $SECSVC;
my $SECHOME;
my $SECUNLOCK;
my $XYMSRV;
my $PORT = 1984;
my $LIFETIME = 30;
my $opt_d = 0;
my $opt_n = 0;

# Private Functions
#
sub rev_by_date {
    $b->[9] <=> $a->[9];
}

sub toggle_debug {
    if ( $opt_d ) {
        $opt_d = 0;
    } else {
        $opt_d = 1;
    }
    return join ( " ", "$SELF", $VERSION, ($opt_d)? "debug is on" : "debug is off");
}

sub mysymlink {
  # needs testing for OS, this is only required in Windows
  my ($oldname,$newname) = @_;
  my $oldfilename = File::Spec->catfile($oldname);
  my $newfilename = File::Spec->catfile($newname);
  if (-f $newfilename) { } else {
    my @args = ("mklink", $newfilename, $oldfilename);
    system(@args) == 0;
  }
}

sub isnumeric {
  my $InputString = shift;
  return 0 if (!defined($InputString));
  if ($InputString !~ /^[0-9|.]+$/) {
    return 0;
  } else {
    return 1;
  }
}

sub setworstcolour {
  # $1=worst $2=color, return worst
  if (( $_[0] ne "red" ) && ( $_[0] ne "yellow" ) ) {
    return $_[1];
  } elsif (( $_[0] ne "red" ) && ( $_[1] eq "yellow" )) {
    return $_[1];
  } elsif ( $_[1] eq "red" ) {
    return $_[1];
  } else {
    return $_[0];
  }
}

sub check_val {
my ($oldcol,$col,$tocheck,$mod,$val) = @_;
  SWITCH: for ($mod) {
    />/ && do {
        if (( &isnumeric($val)) && (&isnumeric($tocheck))) {
          $oldcol=&setworstcolour($oldcol,$col) if ($val>$tocheck);
        }
        last;
      };
    /</ && do {
        if (( &isnumeric($val)) && (&isnumeric($tocheck))) {
          $oldcol=&setworstcolour($oldcol,$col) if ($val<$tocheck);
        }
        last;
      };
    /=/ && do {
        $oldcol=&setworstcolour($oldcol,$col) if ($val =~ /$tocheck/);
        last;
      };
    /!/ && do {
        $oldcol=&setworstcolour($oldcol,$col) if ($val !~ /$tocheck/);
        last;
      };
  }
  return $oldcol;
}

# Exported Functions
#
sub init_sec2xym {
    ($XYMSRV,$PORT,$LIFETIME,$SECSVC,$SECHOME,$opt_d,$opt_n) = @_;
    if ( $WIN32 ) {
        $SECUNLOCK = join ("\\",$SECHOME,"ext","secunlock.cmd");
    } else {
        $SECUNLOCK = join ("/",$SECHOME,"ext","secunlock.sh");
    }
    return "$SELF version $VERSION initialised";
}

# Subroutine to provide access to native signal processing on platforms
# where signals not supported, eg Windows with native perl (ActiveState,
# Strawberry etc)
sub fake_signal_handler {
    my ($fakesignal) = @_;
    given ($fakesignal) {  
        when (/^HUP$/i)   { main::hup_handler; }
        when (/^ABRT$/i)  { main::abrt_handler; }
        when (/^USR1$/i)  { main::usr1_handler; }
        when (/^USR2$/i)  { main::usr2_handler; }
        when (/^INT$/i)   { main::int_handler; }
        when (/^TERM$/i)  { main::term_handler; }
        default: {
                     main::log_msg(main::LOG_WITHOUT_LEVEL,
                         "$SELF Unknown fake signal $fakesignal");
                     return "Unknown fake signal $fakesignal";
                 }
    }
    return 0;
}

# Subroutine to communicate with Xymon
sub sendToXymon {
    use IO::Socket;
    my($server,$port,$msg) = @_ ;
    my $response;
    my @stream;
    # Use an alarm to prevent possible socket blocking.
    #
    my $TIMEOUT_IN_SECONDS = 10;
    eval {
        if ( ! $WIN32 ) {
            local $SIG{ALRM} = sub {return "Socket timeout"};
            alarm($TIMEOUT_IN_SECONDS);
        }

        my $sock = new IO::Socket::INET (
            PeerAddr => $server,
            PeerPort => $port,
            Proto => 'tcp',
            );
        return "Could not create socket: $!" unless $sock;
        print $sock $msg;
        shutdown($sock, 1);
        while ($response=<$sock>) {
            push (@stream, $response);
        }
        close($sock);
        if ( ! $WIN32 ) {
            alarm (0);
        }
    };

    # Handle timeout condition.
    #
    if ($@) {
        return "Socket timeout";
    }
    else {
        # Return results to caller.
        #
        if (@stream && (grep ! /^\s*$/, @stream)) {
            return @stream;
        }
        else {
            return undef;
        }
    }
}

# Subroutine to fetch a named list of files from the Xymon download directory.
# Used as a way to keep SEC rule files (*.sr) in sync.
sub refresh_config {

    my (@files) = @_ ;
    my @output;
    my $refresh = 0;

    chdir join ("/",$SECHOME,"tmp") or return "Cannot change to SEC tmp folder";

    my $msg = "flush filecache";
    my @stream = sendToXymon($XYMSRV, $PORT, $msg);

    # foreach loop execution
    foreach my $p (@files) {
        my($a, $d) = fileparse($p);
        $msg = "download $d$a";

        @stream = sendToXymon($XYMSRV, $PORT, $msg);
        next if ( ! @stream);
        open (CONF, join ("/","..","etc",$a)) || return ("Can't open current $a for reading") ;
        my @file1 = <CONF> ;
        close CONF;

        if (@file1 ~~ @stream) {
            push (@output, "Current $a is up to date.");
        } else {
            if ( $opt_n || !open (CONF, join ("/",">..","etc",$a)) ) {
                main::log_msg(main::LOG_NOTICE, "$SELF Can't open file $a for writing") if !$opt_n;
                open (CONF, '>'.$a) || return ("Unable to create Offline copy of $a");
            } else {
                # make certain we can create a backup
                if ( !open (BACKUP, join ("/",">..","etc","${a}.bak") ) ) {
                    close CONF;
                    return ("Can't open file $a for backup") ;
                }
                # we are going to overwrite the file
                $refresh++;
                print BACKUP @file1;
                close BACKUP;
            }
            print CONF @stream;
            close CONF;
            push (@output, ($opt_n?"Offline copy of":"New")." $a downloaded.");
        }
    }

    if ( $refresh ) {
        main::log_msg(main::LOG_NOTICE, "$SELF detected central configuration change");
        main::abrt_handler;
    } else {
        main::log_msg(main::LOG_NOTICE, "$SELF central configuration check passed");
    }

    chdir $SECHOME or return "Cannot change to SEC home";

    if ( @output && $opt_d ) {
        return @output;
    }
    else {
        return 0;
    }
}

# Subroutine to maintain the named (static) file hard linked to the newest
# object in a given folder 
sub refresh_logpath {

    use Fcntl qw(:flock SEEK_END);
    my @output;

    my ($logpath, $pattern) = @_ ;
    my($hardlink, $DIR) = fileparse($logpath);
    return "must provide a logpath" unless ($DIR);
    #push ( @output, "logpath=$logpath, pattern=$pattern") ;

    my @files;
    my @latest;

    chdir $DIR or return "Error changing to log folder $DIR";
    opendir(my $DH, '.') or return "Error opening $DIR: $!";
    while (defined (my $file = readdir($DH))) {
        #my $path = $DIR . '/' . $file;
        my $path = $file;
        # ignore non-files - automatically does . and ..
        next unless (-f $path );
        if ( !$pattern || $path =~ /$pattern/i ) {
            # re-uses the stat results from '-f'
            push(@files, [ stat(_), $path ]);
        }
        if ( $file eq $hardlink ) {
            @latest=  stat(_);
        }
    }
    closedir($DH);

    my @sorted_files;
    if ( @files ) {
       @sorted_files = sort rev_by_date @files;
    }
    else {
       return "Error, log folder $DIR is empty.";
    }

    my @newest = @{$sorted_files[0]};
    my $name = pop(@newest);
    if ( @latest ) {
        #print join(", ", @latest) . "\n";
        if ( @latest ~~ @newest ) {
            push (@output, "$hardlink->$name is up to date.") ;
        }
        else {
            if ( unlink $hardlink ) {
                #
                push (@output, "unlinked old link, ") ;
            }
            elsif ( $WIN32 ) {
                # if the log has been recreated externally and we couldnt
                # unlink it, and if this is windows then most probably
                # the parent writer still has this locked, so defer to
                # an externally defined script which might execute a
                # Windows unlocker program to delete the file for us.
                if ( -f $SECUNLOCK ) {
                    #main::log_msg(main::LOG_NOTICE, "$SELF resorting to $SECUNLOCK on $hardlink") ;
                    my @args = ("$SECUNLOCK", "$DIR$hardlink" );
                    system (@args) == 0  or return "Cannot delete old link '$hardlink'";
                    # we will test if this worked when we try to recreate the
                    # link in the while loop below
                } else {
                    return "No utility defined to delete old link '$hardlink'";
                }
            }
            else {
                #return "Error unlinking old link '$hardlink' in $DIR";
                open(my $fh, "<", $hardlink) or return "Cannot open old link '$hardlink'";
                flock($fh, LOCK_UN) or return "Cannot unlock old link '$hardlink'";
                push (@output, "unlocked old link, ") ;
                unlink $hardlink or return "Error unlinking old link '$hardlink' in $DIR";
            }
            my $count = 10;
            while ( $count > 0 ) {
                if ( link ( $name, $hardlink ) ) {
                    push (@output, "Successfully refreshed link '$hardlink' in $DIR. ($count attempts remaining)") ;
                    main::log_msg(main::LOG_NOTICE, "$SELF successfully refreshed link '$hardlink' in $DIR. ($count attempts remaining)") ;
                    last;
                }
                select(undef, undef, undef, 0.50);  # sleep of 500 milliseconds
                $count--;
            }
            if ($count == 0 ) {
                push(@output, "Error refreshing link '$hardlink' in $DIR");
                main::log_msg(main::LOG_NOTICE, "$SELF error refreshing link '$hardlink' in $DIR");
            }
        }
    }
    elsif ( $name != $hardlink ) {
        link ( $name, $hardlink ) or return "Error creating new link '$hardlink' in $DIR";
        push (@output, "Successfully created new link '$hardlink' in $DIR.") ;
    }
    else {
        return "hardlink $hardlink in $DIR has been orpaned";
    }

    chdir $SECHOME or return "Cannot change to SEC home";
    if ( @output && $opt_d ) {
         return @output;
    }
    else {
         return 0;
    }
}

# Subroutine to maintain the named (static) file soft linked to the newest
# object in a given folder 
sub relink_logpath {

    use Fcntl qw(:flock SEEK_END);
    my @output;

    my ($logpath, $pattern, $criteria) = @_ ;
    my($softlink, $DIR) = fileparse($logpath);
    return "must provide a logpath" unless ($DIR);
    #push ( @output, "logpath=$logpath, pattern=$pattern") ;

    my @files;
    my @latest;
    my %WarnColor;
    my $col = "green";
    my $timestamp = localtime();

    $WarnColor{'red'}="ALERT";
    $WarnColor{'yellow'}="WARNING";
    $WarnColor{'green'}="NORMAL";

    chdir $DIR or return "Error changing to log folder $DIR";
    opendir(my $DH, '.') or return "Error opening $DIR: $!";
    while (defined (my $file = readdir($DH))) {
        #my $path = $DIR . '/' . $file;
        my $path = $file;
        # ignore non-files - automatically does . and ..
        next unless (-f $path );
        if ( !$pattern || $path =~ /$pattern/i ) {
            # re-uses the stat results from '-f'
            push(@files, [ stat(_), $path ]);
        }
        if ( $file eq $softlink ) {
            @latest=  stat(_);
        }
    }
    closedir($DH);

    my @sorted_files;
    if ( @files ) {
       @sorted_files = sort rev_by_date @files;
    }
    else {
       return "Error, log folder $DIR is empty.";
    }

    my @newest = @{$sorted_files[0]};
    my $name = pop(@newest);

    if ($criteria) {
      my ($keytest,$val1,$val2,$mod)= split(":",$criteria);
      #my $key; my $test;
      my ($key,$test)= split(",",$keytest);
      my $val;
      my $msg;
      $mod="<" if (!$mod);
      $key="mtime" if (!$key);
      $test="files" if (!$test);
      given ($key) {  
        when (/^mtime$/i)   { $val=time()-$newest[9]; }
        default: {
                     main::log_msg(main::LOG_WITHOUT_LEVEL,
                         "$SELF Unknown file criteria $key");
                     return "Unknown file criteria $key";
                 }
      }

      $col=&check_val($col,"yellow",$val1,$mod,$val) if ($val1 || ($val1 =~/0/));
      $col=&check_val($col,"red",$val2,$mod,$val) if ($val2 || ($val2 =~/0/));
      if ($col !~ /green/) {
	#$val=sprintf("time=%d,9=%d", time(),$newest[9]);
        $msg=sprintf ("&%s %s - %s (%s) - %s (%s) has reached the %s level (%s%s) with check (%s)\n",$col,$timestamp,$softlink,File::Spec->catfile($DIR,$name),$key,$val,$WarnColor{$col},$mod,($col =~ /yellow/?$val1:$val2),$criteria);
      }
      else {
	#$val=sprintf("time=%d,9=%d", time(),$newest[9]);
        $msg=sprintf ("&%s %s - %s (%s) last modified %s second%s ago\n",$col,$timestamp,$softlink,File::Spec->catfile($DIR,$name),$val,$val==1?"":"s");
      }
      #my @stream = XymonStatusModify("", "files" , $col ,"$SELF-$name" , $msg);
      my @stream = XymonStatusModify("", $test , $col ,"" , $msg);
      return $msg;
    }

    if ( @latest ) {
        #print join(", ", @latest) . "\n";
        if ( @latest ~~ @newest ) {
            push (@output, "$softlink->$name is up to date.") ;
        }
        else {
            if ( unlink $softlink ) {
                #
                push (@output, "unlinked old link, ") ;
            }
            elsif ( $WIN32 ) {
                # if the log has been recreated externally and we couldnt
                # unlink it, and if this is windows then most probably
                # the parent writer still has this locked, so defer to
                # an externally defined script which might execute a
                # Windows unlocker program to delete the file for us.
                if ( -f $SECUNLOCK ) {
                    #main::log_msg(main::LOG_NOTICE, "$SELF resorting to $SECUNLOCK on $softlink") ;
                    my @args = ("$SECUNLOCK", "$DIR$softlink" );
                    system (@args) == 0  or return "Cannot delete old link '$softlink'";
                    # we will test if this worked when we try to recreate the
                    # link in the while loop below
                } else {
                    return "No utility defined to delete old link '$softlink'";
                }
            }
            else {
                #return "Error unlinking old link '$softlink' in $DIR";
                open(my $fh, "<", $softlink) or return "Cannot open old link '$softlink'";
                flock($fh, LOCK_UN) or return "Cannot unlock old link '$softlink'";
                push (@output, "unlocked old link, ") ;
                unlink $softlink or return "Error unlinking old link '$softlink' in $DIR";
            }
            my $count = 10;
            while ( $count > 0 ) {
                if ( mysymlink ( $name, $softlink ) ) {
                    push (@output, "Successfully refreshed link '$softlink' in $DIR. ($count attempts remaining)") ;
                    main::log_msg(main::LOG_NOTICE, "$SELF successfully refreshed link '$softlink' in $DIR. ($count attempts remaining)") ;
                    last;
                }
                select(undef, undef, undef, 0.50);  # sleep of 500 milliseconds
                $count--;
            }
            if ($count == 0 ) {
                push(@output, "Error refreshing link '$softlink' in $DIR");
                main::log_msg(main::LOG_NOTICE, "$SELF error refreshing link '$softlink' in $DIR");
            }
        }
    }
    elsif ( $name != $softlink ) {
        mysymlink ( $name, $softlink ) or return "Error creating new link '$softlink' in $DIR";
        push (@output, "Successfully created new link '$softlink' in $DIR.") ;
    }
    else {
        return "softlink $softlink in $DIR has been orpaned";
    }

    chdir $SECHOME or return "Cannot change to SEC home";
    if ( @output && $opt_d ) {
         return @output;
    }
    else {
         return 0;
    }
}

# Subroutine to simplify sending a status update to Xymon by providing default
# settings for target name and timestamp and providing flexibility in severity
sub XymonStatusUpdate {
    my ($target,$TEST, $severity, $lifetime, @MSG ) = @_;

    my $color = "green";
    my $timestamp = localtime();
    my @output;

    if ( !$lifetime )                       { $lifetime=$LIFETIME; }
    if ( !$target )                         { $target = hostname(); }
    $target =~ s/\./,/g;

    # Map the Severity to a valid Xymon state
    given ($severity) {  
      when (/^GREEN$/i)                     { $color = "green"; }
      when (/^Normal$/i)                    { $color = "green"; }
      when (/^INFORMATIONAL$/i)             { $color = "green"; }
      when (/^YELLOW$/i)                    { $color = "yellow"; }
      when (/^WARNING$/i)                   { $color = "yellow"; }
      when (/^MINOR$/i)                     { $color = "yellow"; }
      when (/^RED$/i)                       { $color = "red"; }
      when (/^SEVERE$/i)                    { $color = "red"; }
      when (/^MAJOR$/i)                     { $color = "red"; }
      when (/^CRITICAL$/i)                  { $color = "red"; }
      when (/^FATAL$/i)                     { $color = "red"; }
      default:                              { $color = "clear"; }
    }

    my $msg = join ( "\n","status+$lifetime ${target}.$TEST $color $timestamp", @MSG);
    my @stream = sendToXymon($XYMSRV, $PORT, $msg);
    # there is unlikely to be any return from a status update but we can
    # arrange to provide debug feedback to SEC if required.
    #push (@output, $msg);
    #push (@output, "status+$lifetime ${target}.$TEST $color $timestamp");
    #if ( @output && $opt_d ) {
    #if ( @stream || $opt_d ) {
    if ( $opt_d ) {
        push (@output, "update status+$lifetime ${target}.$TEST $color $timestamp");
        return @output;
    }
    else {
        return 0;
    }
}

# Subroutine to simplify sending a modify update to Xymon by providing default
# settings for target name and source and providing flexibility in severity
sub XymonStatusModify {
    my ($target,$TEST, $severity, $source, @MSG ) = @_;

    my $color = "green";
    my $timestamp = localtime();
    my @output;

    if ( !$source )                         { $source=$SELF; }
    if ( !$target )                         { $target = hostname(); }
    $target =~ s/\./,/g;

    # Map the Severity to a valid Xymon state
    given ($severity) {  
      when (/^GREEN$/i)                     { $color = "green"; }
      when (/^Normal$/i)                    { $color = "green"; }
      when (/^INFORMATIONAL$/i)             { $color = "green"; }
      when (/^YELLOW$/i)                    { $color = "yellow"; }
      when (/^WARNING$/i)                   { $color = "yellow"; }
      when (/^MINOR$/i)                     { $color = "yellow"; }
      when (/^RED$/i)                       { $color = "red"; }
      when (/^SEVERE$/i)                    { $color = "red"; }
      when (/^MAJOR$/i)                     { $color = "red"; }
      when (/^CRITICAL$/i)                  { $color = "red"; }
      when (/^FATAL$/i)                     { $color = "red"; }
      default:                              { $color = "clear"; }
    }

    my $msg = join ( "\n","modify ${target}.$TEST $color $source", @MSG);
    my @stream = sendToXymon($XYMSRV, $PORT, $msg);
    # there is unlikely to be any return from a status update but we can
    # arrange to provide debug feedback to SEC if required.
    #push (@output, $msg);
    #push (@output, "status+$lifetime ${target}.$TEST $color $timestamp");
    #if ( @output && $opt_d ) {
    #if ( @stream || $opt_d ) {
    if ( $opt_d ) {
        push (@output, "modify ${target}.$TEST $color $source");
        return @output;
    }
    else {
        return 0;
    }
}

1;
