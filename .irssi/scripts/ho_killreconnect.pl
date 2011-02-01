# ho_killreconnect.pl
#
# $Id: ho_killreconnect.pl,v 1.1 2003/03/23 15:33:12 jvunder Exp $
#
# Part of the Hybrid Oper Script Collection.
#
# Reconnects if you're killed by an oper.
#

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;

$VERSION = '1.00';
%IRSSI = (
    authors	=> 'Garion',
    contact	=> 'garion@efnet.nl',
    name	=> 'ho_killreconnect',
    description	=> 'Hybrid Oper Script Collection - Killreconnect',
    license	=> 'Public Domain',
    url		=> 'http://hosc.garion.org/',
    changed	=> '23 March 2003 16:27:01',
);


Irssi::signal_add('event kill', 
  sub {
    my ($server, $args, $nick, $address) = @_;
    my $reason = $args;
    $reason =~ s/^.*://g;
    Irssi::print("You were killed by $nick ($reason)."); 
    Irssi::signal_stop(); 
  }
);

# Yes, that's all. Explanation:
# <cras> garion: you could probably do that more easily by preventing
#        irssi from seeing the kill signal
# <cras> garion: signal_add('event kill', sub { Irssi::signal_stop(); });
# <cras> garion: to prevent irssi from setting server->no_reconnect = TRUE

Irssi::print("%CHybrid Oper Script Collection%n - Killreconnect");
Irssi::print("Killreconnect script loaded. When killed by an oper, you will be reconnected. See also /set server_reconnect_time.");

# EOF
