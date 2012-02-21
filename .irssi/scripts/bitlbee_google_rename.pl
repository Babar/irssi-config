# renames bitlbee google-via-xmpp buddies to something sane
# Originally by Tim Angus, http://a.ngus.net/bitlbee_rename.pl
# Based on the Facebook version by avar,
#   https://github.com/avar/irssi-bitlbee-facebook-rename.git

# script is for irssi:
# Save it as .irssi/scripts/bitlbee_google_rename.pl
# then /script load bitlbee_google_rename.pl

# known issues: If the name it's renaming to is already taken, the rename fails.

use strict;
use warnings;
use utf8;
use Socket;
use Irssi;
use Irssi::Irc;

my $bitlbeeChannel = "&bitlbee";
my %nicksToRename  = ();
my $matchhostname  = "public.talk.google.com";

sub google_rename_message_join {

    # "message join", SERVER_REC, char *channel, char *nick, char *address
    my ( $server, $channel, $nick, $address ) = @_;

    # _1yuwuj64cnz3p2js21vbfw7!1yuwuj64cnz3p2js21vbfw7@public.talk.google.com
    return
      if $channel ne $bitlbeeChannel
          || $address !~ /^(\w{23})\w{3}\@$matchhostname$/
          || $nick !~ /^_$1$/;

    $nicksToRename{$nick} = $channel;
    $server->command("quote whois $nick");
}

sub google_rename_whois_data {
    my ( $server, $data ) = @_;
    my ( $me, $nick, $user, $host, $ircname ) =
      $data =~ /^(\S+) (\S+) (\S+) (\S+) \* :(.*)$/;

    return unless $host eq $matchhostname;
    if ( my $channel = delete( $nicksToRename{$nick} ) ) {

        $ircname =~ tr/ąäàâçćéèęêëïîńñóôöôüùûłśżźß/aaaacceeeeiinnoooouuulszzs/d;
        $ircname = join "", map { ucfirst } split /\s/, $ircname;
        $ircname =~ s/[^\w]//g;
        $ircname = substr( $ircname, 0, 24 );

        $server->command("msg $channel rename $nick ${ircname}G");
        $server->command("msg $channel save");
    }
}

Irssi::signal_add_first 'message join' => 'google_rename_message_join';
Irssi::signal_add_first 'event 311'    => 'google_rename_whois_data';
