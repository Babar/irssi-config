# renames bitlbee facebook-via-xmpp buddies to something sane
# Originally by Tim Angus, http://a.ngus.net/bitlbee_rename.pl
# Modified slightly to only rename people on chat.facebook.com, and also strip invalid chars from names, by Lakitu7
# copied in a mod by ajf on #bitlbee to only match u###### names
# truncates names over 25 chars to comply with bitlbee's limit; thanks Jesper on #bitlbee

# script is for irssi. Save it as .irssi/scripts/bitlbee_rename.pl then /script load bitlbee_rename.pl
# known issues: If the name it's renaming to is already taken, the rename fails.

use strict;
use Socket;
use Irssi;
use Irssi::Irc;

my $bitlbeeChannel = "&bitlbee";
my %nicksToRename = ();
my $facebookhostname = "chat.facebook.com";

sub message_join
{
  # "message join", SERVER_REC, char *channel, char *nick, char *address
  my ($server, $channel, $nick, $address) = @_;
  my ($username, $host) = $address =~ /^-?([^@]+)\@(.+)$/;
  #my $username = substr($address, 0, index($address,'@'));
  #my $host = substr($address, index($address,'@')+1);

  return unless $channel =~ /$bitlbeeChannel/;
  return unless $nick =~ /^[u-]\d+$/;
  return unless $address =~ /^-?$nick\@$facebookhostname$/;
  $nicksToRename{$nick} = $channel;
  $server->command("quote whois $nick");
}

sub whois_data
{
  my ($server, $data) = @_;
  my ($me, $nick, $user, $host, $ircname) = $data =~ /^(\S+) (\S+) (\S+) (\S+) \* :(.*)$/;

  return unless $host eq $facebookhostname;
  if (my $channel = delete($nicksToRename{$nick}))
  {
    # TODO: Remove accents and such stuff...
#    $ircname =~ tr/ąäàâçćéèęêëïîńñóôöôüùûłśżźß/aaaaaceeeeiinnoooouuulszz/d;
    $ircname =~ s/[^A-Za-z0-9_]//g;
    $ircname = substr( $ircname, 0, 25 );

    $server->command("msg $channel rename $nick $ircname");
    $server->command("msg $channel save");
  }
}

Irssi::signal_add_first 'message join' => 'message_join';
Irssi::signal_add_first 'event 311' => 'whois_data';
