# ho-track.pl
#
# $Id: ho_track.pl,v 1.7 2003/02/26 10:44:07 james Exp $
#
# Part of the Hybrid Oper Script Collection.
#
# This script looks at incoming server notices and finds any unusual
# activity. This is then reported or acted on.

###########################################################################
#
# Feature description:
# - Rapid connections from one host warning, and automatic temp K-line.
# - Warning if a client connects with "inviter" in its realname field.
#
#
###########################################################################

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
use Irssi::TextUI;

# ======[ Script Header ]===============================================

($VERSION) = '$Revision: 1.7 $' =~ / (\d+\.\d+) /;

%IRSSI = (
    authors	=> 'Garion',
    contact	=> 'garion@efnet.nl',
    name	=> 'ho-track',
    description	=> 'Hybrid Oper Script Collection - report or act upon unusual events in server notices',
    license	=> 'Public Domain',
    url		=> 'http://www.garion.org/irssi/hosc.php',
    changed	=> '19 January 2003 13:07:07',
);

# ======[ Credits ]=====================================================
#
# Thanks to:
#

# ======[ Variables ]===================================================

# Irssi scripts dir.
my $scriptdir = Irssi::get_irssi_dir() . "/scripts";

# Hashtable with connection times per host
# Key is the host
# Value is an array of connection times (unix timestamp)
my %conntimes;

# The last time the connection hash has been cleaned (unix timestamp)
my $conntimes_last_cleaned = 0;

# Hashtable with joining juped channel times per host
# Key is the host
# Value is an array of join times (unix timestamp)
my %jupetimes;

# The last time the connection hash has been cleaned (unix timestamp)
my $jupetimes_last_cleaned = 0;

# These are for drone calculations
my %good_occurances;
my %bad_occurances;
my $good_count;
my $bad_count;
my %scores;

# There are for the connection speed statistics
my $minute_connects;
my $total_connects;
my $connection_readings;

# Last time the connection average was calculated
my $last_average_calc;

# ======[ Signal hooks ]================================================

# --------[ event_serverevent ]-----------------------------------------

# A Server Event has occurred. Check if it is a server NOTICE; 
# if so, process it.

sub event_serverevent {
  my ($server, $msg, $nick, $hostmask) = @_;
  my ($nickname, $username, $hostname);

  # If it is not a NOTICE, we don't want to have anything to do with it.
  if ($msg !~ /^NOTICE/) {
    return;
  }
  
  # If the hostmask is set, it is not a server NOTICE, so we'll ignore it
  # as well.
  if (length($hostmask) > 0) {
    return;
  }
  
  my $ownnick = $server->{'nick'};

  # Remove the NOTICE part from the message
  # NOTE: this is probably unnecessary.
  $msg =~ s/^NOTICE $ownnick ://;

  # Remove the server prefix
  # NOTE: this is probably unnecessary.
  #$msg =~ s/^$prefix//;

  # First do some generic processing like monitoring connections,
  # excess floods, hammering, etc.
  process_event($server, $msg);

}


# --------[ process_event ]---------------------------------------------

# This function takes a server notice and matches it with a few regular
# expressions to see if any special action needs to be taken.

sub process_event {
  my ($server, $msg) = @_;

  # HYBRID 7 - need a setting to determine which server type we have!
  # Client connect: nick, user, host, ip, class, realname
  if ($msg =~ /Client connecting: (.*) \((.*)@(.*)\) \[(.*)\] {(.*)} \[(.*)\]/) {
    process_connect($server, $1, $2, $3, $4, $5, $6);
    return;
  }

  # nick, user, host, channel
  if ($msg =~ /User (.*) \((.*)@(.*)\) is attempting to join locally juped channel (.*)/) {
    process_jupe($server, $1, $2, $3, $4);
    return;
  }
  #}

  # HYBRID 6
  # Client connect: nick, user, host, ip, class, realname
  if ($msg =~ /Client connecting: (.*) \((.*)@(.*)\) \[(.*)\] {(.*)}/) {
    process_connect($server, $1, $2, $3, $4, $5, "");
    return;
  }
}

# --------[ process_connect ]-------------------------------------------

# This function processes a client connect.
# It shows warning in case of:
# - possible inviter bots connecting
# - many connects in a short timespan from a single host

sub process_connect {
  my ($server, $nick, $user, $host, $ip, $class, $realname) = @_;

  if ($realname =~ /inviter/i) {
    print_warning("possible inviter bot $nick ($user\@$host) [$realname].");
  }
  
  # Calculate drone score
  my $score = score_word($nick) * score_word($user);

  # ~ in ident has higher probability of cloning
  if ($user =~ /^~/) {
	  $score *= 0.4;
  }

  if (Irssi::settings_get_bool('ho_track_drone_debug')) {
	  Irssi::print("$nick!$user scores $score");
  }

  #make it a manageable number: KLUDGE :/
  $score *= 100000;

  if ($score <= Irssi::settings_get_int('ho_track_drone_limit')) {
    my $tempwin = get_window_by_name("warning");	
    $tempwin->printformat(MSGLEVEL_CRAP, "ho_drone", "$nick", "$user\@$host", sprintf("%5f", $score));
  }
  
  # Update the connection counter
  $minute_connects++;

  #Do this here to avoid fast connection warnins being disabled by the setting below
  #If we've gone 60s without calculating the average, do it now
  if (time() > $last_average_calc + 60) {
	$last_average_calc = time();

    $total_connects += $minute_connects;
    my $average_connects = $total_connects / ++$connection_readings;   
    
    if ($minute_connects > (2 * $average_connects)) {
      my $win = Irssi::active_win();
      $win->printformat(MSGLEVEL_PUBLIC | MSGLEVEL_HILIGHT, "ho_fastloading", $minute_connects, sprintf("%.1f", $average_connects));
    }   
    $minute_connects = 0;
  }

  # Only keep track of connections per host if ho_trackconnections
  # is TRUE.
  if (! Irssi::settings_get_bool('ho_track_hammer_enable')) {
    return;
  }

  # Add this connection time to the array of this host in the connection
  # times hash table.
  push @{ $conntimes{$host} }, time();

  # Check whether this host has connected more than
  # ho_track_hammer_warning_count times in the past
  # ho_track_hammer_warning_time seconds.
  if (@{ $conntimes{$host} } >= 
      Irssi::settings_get_int('ho_track_hammer_warning_count')) {
    # Get the time of the first connect
    my $firsttime = ${ $conntimes{$host} }[0];

    # Get the time of the last connect
    my $lasttime = ${ $conntimes{$host} }[@{ $conntimes{$host} } - 1];

    # Get the time difference between these times
    my $timediff = $lasttime - $firsttime;

    if ($timediff < Irssi::settings_get_int('ho_track_hammer_warning_time')) {
      print_warning("Hammer: " . @{ $conntimes{$host} } . "/".
                   "$timediff: $nick ($user\@$host).");
    }
  }

  # Check whether this host has connected more than
  # ho_track_hammer_violation_count times in the past
  # ho_track_hammer_violation_time seconds.
  if (@{ $conntimes{$host} } >= 
      Irssi::settings_get_int('ho_track_hammer_violation_count')) {
    # Get the time of the first connect
    my $firsttime = ${ $conntimes{$host} }[0];

    # Get the time of the last connect
    my $lasttime = ${ $conntimes{$host} }[@{ $conntimes{$host} } - 1];

    # Get the time difference between these times
    my $timediff = $lasttime - $firsttime;

    if ($timediff < Irssi::settings_get_int('ho_track_hammer_violation_time')) {
      my $time = Irssi::settings_get_int('ho_track_hammer_kline_time');
      my $reason = Irssi::settings_get_str('ho_track_hammer_kline_reason');

      # If number of connections is equal to max number of connections
      # allowed, kline user@host. If it is higher, that means the user
      # has been k-lined once and has changed ident; therefore, kline
      # *@host.
      if (@{ $conntimes{$host} } == Irssi::settings_get_int('ho_track_hammer_violation_count')) {
        print_message("K-lined $user\@$host for hammering.");
        $server->send_raw("KLINE $time $user\@$host :$reason");
      } else {
        print_message("K-lined *\@$host for hammering.");
        $server->send_raw("KLINE $time *\@$host :$reason");
      }
    }
  }

  # Clean up the connection times hash to make sure it doesn't grow
  # to infinity :)
  # Do this every 60 seconds.
  if (time() > $conntimes_last_cleaned + 60) {
    $conntimes_last_cleaned = time();
    cleanup_conntimes_hash(300);
  }
}

# --------[ process_jupe ]----------------------------------------------

sub process_jupe {
  my ($server, $nick, $user, $host, $channel) = @_;

  # Only keep track of jupes per host if ho_track_jupe_enable
  # is TRUE.
  if (! Irssi::settings_get_bool('ho_track_jupe_enable')) {
    return;
  }

  # Add this connection time to the array of this host in the connection
  # times hash table.
  push @{ $jupetimes{$host} }, time();

  my $channel_printed = substr($channel, 1, length($channel));

  # Check whether this client is trying to join strictly forbidden 
  # drone channels
   if (length(Irssi::settings_get_str('ho_track_jupe_bad_channels')) != 0) {
        my $time = Irssi::settings_get_int('ho_track_jupe_bad_channel_time');
        my $reason = Irssi::settings_get_str('ho_track_jupe_bad_channel_reason');
	my $channels = Irssi::settings_get_str('ho_track_jupe_bad_channels');

        if ($channel =~ (/#($channels)/i)) {
        print_message("K-lined *\@$host for bad channels. $channel_printed");
        $server->send_raw("KLINE $time *\@$host :$reason - $channel_printed");
          }
     }

  # Check whether this host has joined more juped channels than
  # ho_track_jupe_warning_count times in the past
  # ho_track_jupe_warning_time seconds.
  my $reason = Irssi::settings_get_str('ho_track_jupe_warning_reason');
  if (@{ $jupetimes{$host} } >= 
      Irssi::settings_get_int('ho_track_jupe_warning_count')) {
    # Get the time of the first join
    my $firsttime = ${ $jupetimes{$host} }[0];

    # Get the time of the last join
    my $lasttime = ${ $jupetimes{$host} }[@{ $jupetimes{$host} } - 1];

    # Get the time difference between these times
    my $timediff = $lasttime - $firsttime;

    if ($timediff < Irssi::settings_get_int('ho_track_jupe_warning_time')) {
      print_warning("Jupe: " . @{ $jupetimes{$host} } . "/".
                   "$timediff: $nick ($user\@$host).");
      $server->command("notice $nick $reason \#$channel_printed");
    }
  }

  # Check whether this host has joined more juped channels than
  # ho_track_jupe_violation_count times in the past
  # ho_track_jupe_violation_time seconds.
  if (@{ $jupetimes{$host} } >= 
      Irssi::settings_get_int('ho_track_jupe_violation_count')) {
    # Get the time of the first join
    my $firsttime = ${ $jupetimes{$host} }[0];

    # Get the time of the last join
    my $lasttime = ${ $jupetimes{$host} }[@{ $jupetimes{$host} } - 1];

    # Get the time difference between these times
    my $timediff = $lasttime - $firsttime;

    if ($timediff < Irssi::settings_get_int('ho_track_jupe_violation_time')) {
      my $time = Irssi::settings_get_int('ho_track_jupe_kline_time');
      my $reason = Irssi::settings_get_str('ho_track_jupe_kline_reason');

      # If number of join is equal to max number of connections
      # allowed, kline user@host. If it is higher, that means the user
      # has been k-lined once and has changed ident; therefore, kline
      # *@host.
      if (@{ $jupetimes{$host} } == Irssi::settings_get_int('ho_track_jupe_violation_count')) {
        print_message("K-lined $user\@$host for juped channels. - $channel_printed");
        $server->send_raw("KLINE $time $user\@$host :$reason - $channel_printed");
      } else {
        print_message("K-lined *\@$host for juped channels. - $channel_printed");
        $server->send_raw("KLINE $time *\@$host :$reason - $channel_printed");
      }
    }
  }
}



# --------[ cleanup_conntimes_hash ]------------------------------------
# Cleans up the connection times hash.
# The only argument is the number of seconds to keep the hostnames for.
# This means that if the last connection from a hostname was longer ago
# than that number of seconds, the hostname is dropped from the hash.

sub cleanup_conntimes_hash {
  my ($keeptime) = @_;
  my @keys = keys(%conntimes);
  my $numkeys = @keys;
  my $now = time();
  
  # If the last time this host has connected is over $keeptime secs ago,
  # delete it.
  foreach my $host (@keys) {
    my $lasttime = ${ $conntimes{$host} }[@{ $conntimes{$host} } - 1];

    # Discard this host if no connections have been made from it during
    # the last $keeptime seconds.
    if ($now > $lasttime + $keeptime) {
      delete($conntimes{$host});
    }
  }
}

# ======[ Helper functions ]============================================

# --------[ get_window_by_name ]----------------------------------------
# Returns the window object given in the setting ho_win_$name.

sub get_window_by_name {
  my ($name) = @_;

  # Get the reference to the window from irssi
  my $win = Irssi::window_find_name($name);

  # If not found, get the reference to window 1
  # I'm hoping that this does ALWAYS exist :)
  # But if not... how can this be improved so to ALWAYS return a valid
  # window reference?
  if (!defined($win)) {
    $win = Irssi::window_find_refnum(1);
  }

  return $win;
}

# --------[ print_warning ]---------------------------------------------
# Prints a warning. If there is a "ho" window present, the warning is
# sent to that window; otherwise, it's sent to the active window.
# The second argument is whether the message needs to be sent with
# the hilight msglevel. Set this to 1 to hilght the message.

sub print_warning {
  my ($warning, $hilight) = @_;

  my $msglevel = MSGLEVEL_PUBLIC;
  if ($hilight == 1) {
    $msglevel = MSGLEVEL_PUBLIC | MSGLEVEL_HILIGHT;
  }

  # Get the window named "ho"
  my $win = Irssi::window_find_name("ho");

  # If this does not exist, get the active window
  if (!defined($win)) {
    #Irssi::print("'ho' window not found.");
    $win = Irssi::active_win();
  }

  $win->printformat($msglevel, "ho_warning", $warning);
}

# --------[ print_message ]---------------------------------------------
# Prints a message. If there is a "ho" window present, the message is
# sent to that window; otherwise, it's sent to the active window.
# The second argument is whether the message needs to be sent with
# the hilight msglevel. Set this to 1 to hilght the message.

sub print_message {
  my ($message, $hilight) = @_;

  my $msglevel = MSGLEVEL_PUBLIC;
  if ($hilight == 1) {
    $msglevel = MSGLEVEL_PUBLIC | MSGLEVEL_HILIGHT;
  }

  # Get the window named "ho"
  my $win = Irssi::window_find_name("ho");

  # If this does not exist, get the active window
  if (!defined($win)) {
    $win = Irssi::active_win();
  }

  $win->printformat($msglevel, "ho_message", $message);
}

# --------[ check_usermodes ]-------------------------------------------
# Checks whether the user has the correct usermodes to use this script
# successfully.

sub check_usermodes {
  my $umode = Irssi::active_win()->{'active_server'}->{'usermode'};
  if ($umode !~ /o/) {
    Irssi::print("You'll need to oper up to use this script.");
  }
  if ($umode !~ /c/) {
    Irssi::print("You'll need to set /umode +c to use this script.");
  }
}

# ======[ Commands ]====================================================

# --------[ cmd_track ]-------------------------------------------------
# The /track command.

sub cmd_track {
  my ($data, $server, $item) = @_;
  if ($data =~ m/^[(help|average)]/i ) {
    Irssi::command_runsub ('track', $data, $server, $item);
  }
  else {
    Irssi::print("Use /track help.")
  }
}

# JMS
sub cmd_drone {
  my ($data, $server, $item) = @_;
  Irssi::print("Score for string $data is " . score_word($data,1));
}


# --------[ cmd_track_help ]--------------------------------------------
# The /track help command.

sub cmd_track_help {
  my ($data, $server, $item) = @_;
  Irssi::print(
"%CHybrid Oper Script Collection%n.\n".
"%GServer notice tracking script%n.\n\n".

"For now, this script does just 2 things:\n".
"- Show a warning whenever a client with \"inviter\" in its realname ".
"connects; and\n".
"- Keep track of rapid (re)connections from a single host and print a ".
"warning or even auto-temp-K-line that host.\n\n".

"Settings:\n".
"bool %_ho_track_hammer_enable%_ - whether to track (re)connections from a ".
"single host\n".
"int %_ho_track_hammer_warning_count%_ and ".
"int %_ho_track_hammer_warning_time%_ - if more than this count of ".
"connections has been made within this time from a single host, print ".
"a warning message.\n".
"int %_ho_track_hammer_violation_count%_ and ".
"int %_ho_track_hammer_violation_time%_ - if more than this count of ".
"connections has been made within this time from a single host, temp K-line ".
"the last user\@host.\n".
"int %_ho_track_hammer_kline_time%_ - time of temp K-line (minutes)\n".
"str %_ho_track_hammer_kline_reason%_ - reason of temp K-line.\n\n".

"The same settings apply for jupe instead of hammer.\n".
"Note that by default, automatic K-lines for excessive juped channel joining ".
"are enabled, and hammering K-lines are not enabled.\n\n".

"If there is a window named %cho%n, the (warning) messages this script ".
"generates will be sent there. If not, they will be sent to the active ".
"window.".

"", MSGLEVEL_CLIENTCRAP);
}

# --------[ cmd_track_average ]---------------------------------------------

# The /track average command
sub cmd_track_average {
  my ($data, $server, $item) = @_;

  if ($data eq "") {
	  if ($connection_readings == 0) {
		  Irssi::print("Not enough data yet.");
		  return;
	  }
	  Irssi::print("Average connections/min: " . $total_connects / $connection_readings);
	  Irssi::print("Connections so far this minute: " . $minute_connects);
	  return;
  }

  my $new_connects = $data;
  Irssi::print("Setting average to $new_connects...");
  $new_connects *= $connection_readings;
  $total_connects = $new_connects;
}


# --------[ score_word --]---------------------------------------------------

# Calculate the score for a word
#
# This code is a MESS and UNOPTIMISED kthx
sub score_word {
	my ($string, $debug) = @_;
	my $score = 1;
	my $debug_string = "";

	$string .= "  ";

	my @chars = unpack("A2" x (length($string)/2), $string);
	foreach my $char (@chars) {
		next if (length($char) < 2);
		if (exists($scores{$char})) {
			$score *= $scores{$char};
			$debug_string .= "$char(" . sprintf("%3f",$scores{$char}). ") ";
		} else {
			$score *= 0.8;
		}

	}

	@chars = unpack("x1" . "A2" x ((length($string)-1)/2), $string);
	foreach my $char (@chars) {
		next if (length($char) < 2);
		if (exists($scores{$char})) {
			$score *= $scores{$char};
			$debug_string .= "$char(" . sprintf("%3f",$scores{$char}). ") ";
		} else {
			$score *= 0.8;
		}
	}	

	$string .= " ";

	@chars = unpack("A3" x (length($string)/3), $string);
	foreach my $char (@chars) {
		next if (length($char) < 3);
		if (exists($scores{$char})) {
			$score *= $scores{$char};
			$debug_string .= "$char(" . sprintf("%3f",$scores{$char}). ") ";
		} else {
			$score *= 0.8;
		}
	}	

	@chars = unpack("x1" . "A3" x ((length($string)-1)/3), $string);
	foreach my $char (@chars) {
		next if (length($char) < 3);
		if (exists($scores{$char})) {
			$score *= $scores{$char};
			$debug_string .= "$char(" . sprintf("%3f",$scores{$char}). ") ";
		} else {
			$score *= 0.8;
		}
	}

	@chars = unpack("x2" . "A3" x ((length($string)-2)/3), $string);
	foreach my $char (@chars) {
		next if (length($char) < 3);
		if (exists($scores{$char})) {
			$score *= $scores{$char};
			$debug_string .= "$char(" . sprintf("%3f",$scores{$char}). ") ";
		} else {
			$score *= 0.8;
		}
	}

	if (Irssi::settings_get_bool('ho_track_drone_debug')) {
		Irssi::print("$string scores $score");
    }

	if ($debug == 1) {
		Irssi::print($debug_string);
	}

	return $score;
}


# --------[ scan_words ]-------------------------------------------

# Load the wordlists from ~/goodnicks.txt and ~/badnicks.txt
# Like the score calculation above, this is KLUDGY, MESSY, and
# very INEFFICIENT. To be fixed :)
sub scan_words {
	my ($filename) = @_;

	open(INPUT, $filename) or return;

	my $total_elements = 0;
	my $count = 0;
	my %occurances;

	while (<INPUT>) {
		my $string = $_;
		last if ($string eq "___\n");
		
		#strip chars that aren't allowed in nicks
		$string =~ s/[^A-Za-z0-9\[\]\{\}^_`\|-]//g;
		
		last if (length($string) < 2);

		my @chars = unpack("A2" x (length($string)/2), $string);
		foreach my $char (@chars) {
			next if (length($char) < 2);
			$total_elements++;
			$count = $occurances{$char};
			$count++;
			$occurances{$char} = $count;
		}	

		@chars = unpack("x1" . "A2" x ((length($string)-1)/2), $string);
		foreach my $char (@chars) {
			next if (length($char) < 2);
			$total_elements++;
			$count = $occurances{$char};
			$count++;
			$occurances{$char} = $count;
		}

		@chars = unpack("A3" x ((length($string))/2), $string);
		foreach my $char (@chars) {
			next if (length($char) < 3);
			$total_elements++;
			$count = $occurances{$char};
			$count++;
			$occurances{$char} = $count;
		}

		@chars = unpack("x1" . "A3" x ((length($string)-1)/2), $string);
		foreach my $char (@chars) {
			next if (length($char) < 2);
			$total_elements++;
			$count = $occurances{$char};
			$count++;
			$occurances{$char} = $count;
		}

		@chars = unpack("x1" . "A3" x ((length($string)-2)/2), $string);
		foreach my $char (@chars) {
			next if (length($char) < 2);
			$total_elements++;
			$count = $occurances{$char};
			$count++;
			$occurances{$char} = $count;
		}
	}
	return %occurances;
}

# ======[ Setup ]=======================================================

# --------[ Register signals ]------------------------------------------

Irssi::signal_add_first('server event', 'event_serverevent');

# --------[ Register commands ]-----------------------------------------

Irssi::command_bind('track', 'cmd_track');
Irssi::command_bind('track help', 'cmd_track_help');
Irssi::command_bind('track average', 'cmd_track_average');
Irssi::command_bind('drone', 'cmd_drone');


# --------[ Register settings ]-----------------------------------------

Irssi::settings_add_bool('ho', 'ho_track_hammer_enable', 0);
Irssi::settings_add_int('ho', 'ho_track_hammer_warning_count', 8);
Irssi::settings_add_int('ho', 'ho_track_hammer_warning_time', 100);
Irssi::settings_add_int('ho', 'ho_track_hammer_violation_count', 10);
Irssi::settings_add_int('ho', 'ho_track_hammer_violation_time', 120);
Irssi::settings_add_int('ho', 'ho_track_hammer_kline_time', 1440);
Irssi::settings_add_str('ho', 'ho_track_hammer_kline_reason', '[Automated K-line] Reconnecting too fast. Please try again later.');

Irssi::settings_add_bool('ho', 'ho_track_jupe_enable', 1);
Irssi::settings_add_int('ho', 'ho_track_jupe_warning_count', 4);
Irssi::settings_add_str('ho', 'ho_track_jupe_warning_reason', '[Automated Notice] Please do not join this channel again. This channel has been made unavailable by server administration: ');
Irssi::settings_add_int('ho', 'ho_track_jupe_warning_time', 20);
Irssi::settings_add_int('ho', 'ho_track_jupe_violation_count', 5);
Irssi::settings_add_int('ho', 'ho_track_jupe_violation_time', 30);
Irssi::settings_add_int('ho', 'ho_track_jupe_kline_time', 1440);
Irssi::settings_add_str('ho', 'ho_track_jupe_kline_reason', '[Automated K-line] Repeated attempts to join unavailable channels. Try another server.');
Irssi::settings_add_str('ho', 'ho_track_jupe_bad_channels', '');
Irssi::settings_add_str('ho', 'ho_track_jupe_bad_channel_reason', '[Automated K-line] Attempt to join bad drone channel.');
Irssi::settings_add_int('ho', 'ho_track_jupe_bad_channel_time', 1440);
Irssi::settings_add_str('ho', 'ho_track_jupe_bad_channel_reason', '[Automated K-line] Attempt to join bad drone channel.');
Irssi::settings_add_int('ho', 'ho_track_jupe_bad_channel_time', 1440);
Irssi::settings_add_bool('ho', 'ho_track_drone_debug', 0);
Irssi::settings_add_int('ho', 'ho_track_drone_limit', 1);

# --------[ Intialization ]---------------------------------------------

Irssi::print("%CHybrid Oper Script Collection%n - Server Notice Tracking");

# Register all ho formats
Irssi::theme_register( [
    'ho_crap',
    '{line_start}%Cho:%n $0',

    'ho_warning',
    '{line_start}%Cho:%n %RWarning%n $0',

    'ho_message',
    '{line_start}%Cho:%n $0',
    
    'ho_drone',
    '{line_start}%rDRONE%n Possible drone {nick $0} {chanhost $1} {comment $2}',
    
    'ho_fastloading',
    '{line_start}%RCONNECT%n Loading clients too fast: {hilight $0}/min {comment avg $1/min}',
    
    'ho_veryfastloading',
    '{line_start}%RCONNECT%n Loading clients too fast: {hilight $0}/min'
] );

# Load drone data
my $datadir = Irssi::get_irssi_dir();

Irssi::print "Reading in good nick list...";
%good_occurances = scan_words("$datadir/goodnicks.txt");

Irssi::print "Reading in bad nick list...";
%bad_occurances = scan_words("$datadir/badnicks.txt");

my @good_keys = keys %good_occurances;
my @bad_keys = keys %bad_occurances;

$good_count = $#good_keys;
$bad_count = $#bad_keys;

Irssi::print "good: $good_count .. bad: $bad_count";

Irssi::print "Reticulating splines...";
foreach my $element (@good_keys) {
	my $element_good = $good_occurances{$element};
	my $element_bad = 0;
	if ($element_bad = $bad_occurances{$element}) {
		my $score = ($element_good/$good_count) / ($element_bad/$bad_count + ($element_good/$good_count));
		$scores{$element} = $score;
	}
}

#free some memory
undef @good_keys;
undef @bad_keys;
undef %good_occurances;
undef %bad_occurances;

# See if there's a window named "ho".
if (!defined(Irssi::window_find_name("ho"))) {
  Irssi::print("No window named %cho%n found. Sending data to the active window.");
} else {
  Irssi::print("Sending data to window %cho%n.");
}

# Check whether the user has the proper usermodes.
check_usermodes();

Irssi::print("%GServer Notice Tracking%n script loaded. Use /TRACK HELP for help.", MSGLEVEL_CRAP);

# ======[ END ]=========================================================
