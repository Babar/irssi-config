# INSTALLATION
#
# - Add the statusbar item:
#    /statusbar window add typing_notice
#    You won't see anything until someone is typing.
#
# - To receive typing notifications with BitlBee, say this in the BitlBee channel:
#   set typing_notice true
#   Then root will reply to confirm the setting:
#   <@root> typing_notice = `true'
# 
# SETTINGS
#
# [typing_notice]
# send_typing = ON
#   -> send typing notifications to supported users
# all_windows = OFF
#   -> show typing notifications in all windows
#
# 
# CHANGES
#
# 2007-05-29 (version 1.9.1)
# * timer_out is set to 0 when message is sent.
#
# 2007-05-24 (version 1.9) (BETA)
# * Huge changes to support typing notices on IRC.
# * All the users, timers, and timouts are stored in one hash call %typers.
# * Matt 'Forked' Sparks is removed from the $IRSSI->{authors} hash. There are still some pieces of code from him in this script though, Thanks!
#
# 2007-03-03 (version 1.6.2)
# * Fix: timers weren't deleted correctly. This resulted in huge mem usage.
#
# 2006-11-02 (version 1.6.1)
# * Sending typing works again.
#
# 2006-10-27 (version 1.6)
# * 'channel sync' re-implemented.
# * bitlbee_send_typing was a string setting, It's a boolean now, like it should.
#
# 2006-10-24 (version 1.5)
# * Sending notices to online users only.
# * Using the new get_channel function;
#
# 2005-12-15 (version 1.42):
# * Fixed small bug with typing notices disappearing under certain circumstances
#   in channels
# * Fixed bug that caused outgoing notifications not to work 
# * root cares not about our typing status.
#
# 2005-12-04 (version 1.41):
# * Implemented stale states in statusbar (shows "(stale)" for OSCAR connections) 
# * Introduced bitlbee_typing_allwin (default OFF). Set this to ON to make
#   typing notifications visible in all windows.
#
# 2005-12-03 (version 1.4):
# * Major code cleanups and rewrites for bitlbee 1.0 with the updated typing
#   scheme. TYPING 0, TYPING 1, and TYPING 2 are now supported from the server.
# * Stale states (where user has typed in text but has stopped typing) are now
#   recognized.
# * Bug where user thinks you are still typing if you close the window after
#   typing something and then erasing it quickly.. fixed.
# * If a user signs off while they are still typing, the notification is removed
# This update by Matt "f0rked" Sparks
#
# 2005-08-26:
# Some fixes for AIM, Thanks to Dracula.
#
# 2005-08-16:
# AIM supported, for sending notices, using CTCP TYPING 0. (Use the AIM patch from Hanji http://get.bitlbee.org/patches/)
# 
# 2004-10-31:
# Sends typing notice to the bitlbee server when typing a message in irssi. bitlbee > 0.92
#
# 2004-06-11:
# shows [typing: ] in &bitlbee with multiple users.
#
use strict;
use Irssi::TextUI;
use Data::Dumper;

use vars qw($VERSION %IRSSI);

$VERSION = '1.9.1';
%IRSSI = (
    authors     => 'Tijmen "timing" Ruizendaal',
    contact     => 'tijmen.ruizendaal@gmail.com',
    name        => 'typing_notice',
    description => '1. Receiving typing notices: Adds an item to the status bar which says [typing] when someone is typing a message.
                    2. Sending typing notices: Sends CTCP TYPING messages to BitlBee users and IRC users (If they support it)',
    license     => 'GPLv2',
    url         => 'http://the-timing.nl/stuff/irssi-bitlbee',
    changed     => '2007-05-29',
);

my $debug = 0;

my $bitlbee_channel = "&bitlbee"; #defaults
my $bitlbee_server_tag = "localhost";

my $KEEP_TYPING_TIMEOUT = 6;
my $STOP_TYPING_TIMEOUT = 7;

my %typers; # for storage

my $line;
my $lastkey;
my $keylog_active = 1;
my $command_char = Irssi::settings_get_str('cmdchars');
my $to_char = Irssi::settings_get_str("completion_char");

## IRC only ##############
my $o = "\cO";
my $oo = $o.$o;
##########################

get_channel();

Irssi::signal_add_last 'channel sync' => sub {
        my( $channel ) = @_;
        if( $channel->{topic} eq "Welcome to the control channel. Type \x02help\x02 for help information." ){
                $bitlbee_server_tag = $channel->{server}->{tag};
                $bitlbee_channel = $channel->{name};
		get_bitlbee_nicks($channel);
        }
};

sub get_channel {
        my @channels = Irssi::channels();
        foreach my $channel(@channels) {
                if ($channel->{topic} eq "Welcome to the control channel. Type \x02help\x02 for help information.") {
                        $bitlbee_channel = $channel->{name};
                        $bitlbee_server_tag = $channel->{server}->{tag};
			get_bitlbee_nicks($channel);
			return 1;
                }
        }
	return 0;
}

sub get_bitlbee_nicks {
	my $channel = shift;
	my @nicks = $channel->nicks();
	foreach my $nick(@nicks) {	
		if ( not exists( $typers{$bitlbee_server_tag}{$nick->{nick}} ) ) {
			$typers{$bitlbee_server_tag}{$nick->{nick}}{timer_out} = 0;
		}
	}
	if ($debug) {
		print Dumper (%typers);
	}
}

sub get_current {
	my $server = Irssi::active_server();
        my $window = Irssi::active_win();
	if ($server && $window) {
		return ($server->{tag}, $window->get_active_name());
	}
	return undef;
}

sub event_ctcp_msg {
	my ($server, $msg, $from, $address) = @_;
	$server = $server->{tag};

	if ( my($type) = $msg =~ /TYPING ([0-9])/ ) {
		if ( not $debug ) {
	        	Irssi::signal_stop();
		}

	        if ($type == 0) {

        		unset_typing_in([$server, $from]);

	        } elsif ($type == 1) {
	
			$typers{$server}{$from}{typing_in} = 1;

		        if ($address !~ /\@login\.oscar\.aol\.com/ and $address !~ /\@YAHOO/ and $address !~ /\@login\.icq\.com/) {

	                	Irssi::timeout_remove($typers{$server}{$from}{timer_tag_in});
				$typers{$server}{$from}{timer_tag_in} = Irssi::timeout_add_once( 
										$STOP_TYPING_TIMEOUT * 1000, 
										"unset_typing_in", 
										[$server, $from]
									);
	            	}

        		Irssi::statusbar_items_redraw('typing_notice');

	        } elsif ( $type == 2 ) {
			$typers{$server}{$from}{typing_in} = 2;
        		Irssi::statusbar_items_redraw('typing_notice');
        	}
    	}
}

sub unset_typing_in {
	my ($a) = @_;
	my ($server, $nick) = @{$a};
	if ($debug) {
		print "unset: $server, $nick";
	}
    	$typers{$server}{$nick}{typing_in} = 0;
    	Irssi::timeout_remove($typers{$server}{$nick}{timer_tag_in});
    	Irssi::statusbar_items_redraw('typing_notice');
}

sub event_msg {
	my ($server, $data, $nick, $address, $target) = @_;
	$server = $server->{tag};

    	if ( $data =~ /$oo\z/ ) {
		if ( not exists( $typers{$server}{$nick} ) ) {
			$typers{$server}{$nick}{timer_out} = 0;
			if ($debug) {
				print "This user supports typing! $server, $nick";
			}
		}
	} else {
		if ( exists( $typers{$server}{$nick} ) && $server ne $bitlbee_server_tag ) { 
			if ($debug) {
				print "This user does not support typing anymore! $nick. splice: ";
			}
			delete $typers{$server}{$nick};
		}
	}
	
	if ( exists( $typers{$server}{$nick} ) ) {
		unset_typing_in( [$server, $nick] );
	}
}

sub event_join {
	my ( $server, $channel, $nick, $address ) = @_;
	$server = $server->{tag};

	if ( $server eq $bitlbee_server_tag ) {
		if ($debug) {
			print "This ($nick) is a bitlbee-user, so we add this to the typers hash.";
		}
		$typers{$server}{$nick}{typing_in} = 0;
	}
}

sub event_quit {
	my ( $server, $nick, $address, $reason) = @_;
	$server = $server->{tag};

	if ( $typers{$server}{$nick}{typing_in} > 0 ) {
	    	unset_typing_in ( [$server, $nick] );
	}
	if ( $server eq $bitlbee_server_tag ) {
		delete $typers{$server}{$nick};
	}
}

sub typing_notice { ## incoming statusbar item
    	my ($item, $get_size_only) = @_;
	my ($server, $channel) = get_current();

	if ( not exists( $typers{$server}{$channel} ) ) {
    		if ($channel eq $bitlbee_channel || $channel =~ /&chat_[0-9]+/ || Irssi::settings_get_bool("all_windows")) {
			while ( my ($key1, $value1) = each(%typers) ) {
				my %typer = %{$value1};
				while ( my ($key2, $value2) = each(%typer) ) {
					if ( $typer{$key2}{typing_in} > 0 ) {
						$line .= " ".$key2;
						if ( $typer{$key2}{typing_in} == 2 ) {
							$line .= " (stale)";
						}
					}
				}
    			}
	        	if ($line ne "") {
	            		$item->default_handler($get_size_only, "{sb typing:$line}", 0, 1);
	            		$line = "";
	        	}
	    	} 	
		return 1;
	}
 
    	if ( $typers{$server}{$channel}{typing_in} > 0 ) {
        	my $append = $typers{$server}{$channel}{typing_in} == 2 ? " (stale)" : "";
	        $item->default_handler($get_size_only, "{sb typing$append}", 0, 1);
		if ($debug) {
			print "typing: $server, $channel.";
		}
    	} else {
		if ($debug) {
			print "clear: $server, $channel ";
		}
	        $item->default_handler($get_size_only, "", 0, 1);
	        Irssi::timeout_remove($typers{$server}{$channel}{timer_tag_in});
		$typers{$server}{$channel}{timer_tag_in} = undef;
    	}
}

sub window_change {
	Irssi::statusbar_items_redraw('typing_notice');
	my ($server, $channel) = get_current();
	
    	if ( exists( $typers{$server}{$channel} ) ) {
        	if ( not $keylog_active ) {
            		$keylog_active = 1;
            		Irssi::signal_add_last('gui key pressed', 'key_pressed');
        	}
    	} else {
        	if ($keylog_active) {
            		$keylog_active = 0;
            		Irssi::signal_remove('gui key pressed', 'key_pressed');
        	}
    	}
}

sub key_pressed {
	return if not Irssi::settings_get_bool("send_typing");
    	my $key = shift;
    	if ($key == 9 && $key == 10 && $lastkey == 27 && $key == 27 && $lastkey == 91 && $key == 126 && $key == 127) { # ignore these keys
		$lastkey = $key;
		return 0;
	}
        
	my ($server, $channel) = get_current();

	if ( exists( $typers{$server}{$channel} ) || $channel eq $bitlbee_channel ) {
              	my $input = Irssi::parse_special("\$L");
       		if ( $channel eq $bitlbee_channel ) {
              		my ($first_word) = split(/ /,$input);
               		if ($input !~ /^$command_char.*/ && $first_word =~ s/$to_char$//){
               			send_typing( $server, $first_word );
               		}
       		} else {
               		if ($input !~ /^$command_char.*/ && length($input) > 0){
               			send_typing( $server, $channel );
              		}
       		}
    	}
    	$lastkey = $key; # some keys, like arrow-up, contain two events. 
}

sub send_typing_stop {
	my ($a) = @_;
    	my( $server, $nick ) = @{$a};
	if ($debug) {
		print "send typing stop $server, $nick.";
	}

	$typers{$server}{$nick}{timer_out} = 0;
	Irssi::timeout_remove($typers{$server}{$nick}{timer_tag_out});
    	
	if ( my $server = Irssi::server_find_tag($server) ) {
        	$server->command("^CTCP $nick TYPING 0");
    	}
}

sub send_typing {
	my ( $server, $nick ) = @_;
	
	if ($debug) {
		print "send typing $server, $nick";
	}

	if ( not exists($typers{$server}{$nick} ) ) {
		if ($debug) {
			print "user doesn't support typing: $server, $nick";
		}
		return 0;
	}

    	if ( time - $typers{$server}{$nick}{timer_out} > $KEEP_TYPING_TIMEOUT || $typers{$server}{$nick}{timer_out} == 0 ) {

        	my $serverobj = Irssi::server_find_tag($server);
	        $serverobj->command("^CTCP $nick TYPING 1");
		if ($debug) {
			print "$server: ^CTCP $nick TYPING 1";
		}
	               
	        $typers{$server}{$nick}{timer_out} = time;
	        
	        Irssi::timeout_remove($typers{$server}{$nick}{timer_tag_out});
	        $typers{$server}{$nick}{timer_tag_out} = Irssi::timeout_add_once($STOP_TYPING_TIMEOUT*1000, 'send_typing_stop', [$server, $nick]);
    	}
}

sub db_typing { 
	print "------ Typers -----\n".Dumper(%typers);	
}

sub event_send_msg { # outgoing messages
	my ($msg, $server, $window) = @_;
	my $nick = $window->{name};

	if ($debug) {
		print "send msg: $server->{tag}, $nick";
	}
	if ( $window->{type} eq "QUERY" && exists( $typers{$server->{tag}}{$nick} )) {
		$typers{$server->{tag}}{$nick}{timer_out} = 0;
		Irssi::timeout_remove($typers{$server->{tag}}{$nick}{timer_tag_out});	
	}

	if ($server->{tag} eq $bitlbee_server_tag ) {
		return 0;
	}

	if (length($msg) > 0) {
		$msg .= $oo;
	}
	
	Irssi::signal_stop();
	Irssi::signal_remove('send text', 'event_send_msg');
	Irssi::signal_emit('send text', $msg, $server, $window);
	Irssi::signal_add_first('send text', 'event_send_msg');
}

# Command
Irssi::command_bind('db_typing','db_typing');

# Settings
Irssi::settings_add_bool("typing_notice","send_typing",1);
Irssi::settings_add_bool("typing_notice","all_windows",0);

# IRC events
Irssi::signal_add_first("send text", "event_send_msg"); # Outgoing messages
Irssi::signal_add("ctcp msg", "event_ctcp_msg");
Irssi::signal_add("message private", "event_msg");
Irssi::signal_add("message public", "event_msg");
Irssi::signal_add("message quit", "event_quit");
Irssi::signal_add("event join", "event_join");

# GUI events
Irssi::signal_add_last('window changed', 'window_change');
Irssi::signal_add_last('gui key pressed', 'key_pressed');

# Statusbar
Irssi::statusbar_item_register('typing_notice', undef, 'typing_notice');
Irssi::statusbars_recreate_items();

