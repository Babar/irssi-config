use strict;
use warnings;

my $VERSION = "0.1";
my %IRSSI   = (
    authors     => 'Bazerka',
    contact     => 'bazerka at quakenet org',
    name        => 'deoperit',
    description => 'Guard against non-opers getting chanmode +o',
    licence     => 'BSD',
    changed     => 'Wed  2 Jun 2010 15:30:14 BST',
    url         => 'n/a',
);

######### deoperit.pl
#
# This script is designed to automatically remove chanops from users that aren't opered up.
#
# It performs a USERHOST on users joining the monitored channels and if detected as an oper,
# places the oper's host into a cache. Once the host is in the cache, this will prevent the
# script from deopping that oper when someone ops them.
#
# If a un-opered user joins the channel and subsequently opers up, they will be de-opped upon
# a user opping them, a USERHOST will be performed and then upon confirmation of being an opered
# user, the script will re-op them.
#
# The cache is pretty simplistic and stores the time of initial entry for a host into the cache.
#
#

########## Thanks to:
#
# Babar for pointing out a few style nits.
#

########## PLEASE NOTE:
#
# This script won't recognise cached opers who are using (fake|set)hosts.
# USERHOST sees through such hosts and will mismatch against what is stored
# in Irssi::Irc::Nick->{host} for that oper (ie, the (fake|set)host.) As this
# script is designed primarily for use on IRCnet, this shouldn't be an issue.
#

########## History:
#
# v0.1 : Initial revision
#

########## Settings:
#
#  /set deoperit_channels <string>
#        <string> : Space seperated list of chatnet:#channel for which deoperit
#                   should monitor (eg, ircnet:#bazfoo ircnet:#foobar)
#
#  /set deoperit_reop_check_delay <time>
#        <time>   : If a user is given chanops and is not present in the cache, how long to wait
#                   after de-opping them to re-op them if the USERHOST shows them to be an oper.
#                   (default: 10s)
#
#  /set deoperit_max_cache_age <time>
#        <time>   : How long a host can survive in the cache before expiring.
#                   (default: 24h)
#
#  /set deoperit_expire_cache_period <time>
#        <time>   : How often to run the cache expiry cleanup.
#                   (default: 1h)
#
#  /set deoperit_debug <ON|OFF>
#        <ON>     : Make lots of noise about what's going on.
#        <OFF>    : !Make lots of noise about what's going on.
#

sub event_nick_mode($$$$$);
sub event_join($$$$);
sub event_redir_userhost($$);
sub event_redir_userhost_timeout($$);
sub reop_check(\@);
sub request_userhost($$$);
sub expire_cache();
sub get_settings();

my %monitored_channels = ();
my %opers              = ();

my $reop_check_delay;
my $max_cache_age;
my $expire_cache_period;
my $expire_cache_timer_id;
my $debug;

sub event_nick_mode($$$$$)
{
    my ( $chan, $nick, $setby_nick, $mode, $type ) = @_;
    return unless ( $mode eq '@' && $type eq '+' );

    my $server   = $chan->{server};
    my $chatnet  = lc( $server->{chatnet} );
    my $channame = lc( $chan->{name} );
    return unless ( exists $monitored_channels{$chatnet}->{$channame} );

    if ( !exists $opers{$chatnet}->{ $nick->{host} } )
    {
        $server->command("mode $chan->{name} -o $nick->{nick}");
        request_userhost( $server, $nick->{nick}, 0 );
        Irssi::timeout_add_once( $reop_check_delay, 'reop_check', [ $server->{tag}, $channame, $nick->{nick} ] );
        printf( "Added reop_check for %s on %s:%s", $nick->{nick}, $server->{tag}, $channame ) if $debug;
    }
}

sub reop_check(\@)
{
    my ( $tag, $channame, $nickname ) = @{ $_[0] };

    # jump through the following hoops incase we've disconnected from the server,
    # parted the channel, the re-op candidate has left the channel or changed their
    # nick since the reop_check was queued.

    my $server_rec = Irssi::server_find_tag($tag);
    return unless ( defined $server_rec && $server_rec->{connected} );

    my $channel_rec = $server_rec->channel_find($channame);
    return unless defined $channel_rec;

    my $nick_rec = $channel_rec->nick_find($nickname);
    return unless defined $nick_rec;

    if ( exists $opers{ lc( $server_rec->{chatnet} ) }->{ $nick_rec->{host} } )
    {
        $server_rec->command("mode $channel_rec->{name} +o $nick_rec->{nick}");
    }
}

sub event_join($$$$)
{
    my ( $server, $chan, $nick, $host ) = @_;
    my $chatnet = lc( $server->{chatnet} );
    return unless ( exists $monitored_channels{$chatnet}->{ lc($chan) } );
    request_userhost( $server, $nick, 1 );
}

sub event_redir_userhost($$)
{
    my ( $server, $data ) = @_;
    my $response = ( split ' :', $data, 2 )[1];
    return if $response eq '';

    my ( $nick, $user, $host ) = ( $response =~ /^(.*?)=.(.*?)@(.*?)$/ );

    if ( substr( $nick, -1 ) eq '*' )
    {
        printf( 'Oper found: %s - adding %s@%s to cache.', $nick, $user, $host ) if $debug;
        $opers{ lc( $server->{chatnet} ) }->{"$user\@$host"} = time();
    }
}

sub event_redir_userhost_timeout($$)
{
    print "$IRSSI{name}: timeout/error occurred waiting for USERHOST response.";
}

sub request_userhost($$$)
{
    my ( $server, $nick, $type ) = @_;

    printf( "Requesting %s USERHOST for %s on %s", $type ? "on-join" : "on-op", $nick, $server->{chatnet} ) if $debug;

    $server->redirect_event(
        'userhost',
        1, $nick, 0,
        'redir deoperit_userhost_timeout',
        {
            'event 302' => 'redir deoperit_userhost',
            ''          => 'event empty',
        }
    );

    $server->send_raw("USERHOST $nick");
}

sub expire_cache()
{
    my $i = 0;
    while ( my ( $chatnet, $value ) = each %opers )
    {
        while ( my ( $host, $time ) = each %{ $opers{$chatnet} } )
        {
            if ( ( time() - $time ) > $max_cache_age )
            {
                printf( "expire_cache: %s is older than %ds, removing from cache", $host, $max_cache_age ) if $debug;
                delete $opers{$chatnet}->{$host};
                $i++;
            }
        }
    }
    printf( "expire_cache: removed %d hosts from cache", $i ) if $debug;
}

sub get_settings()
{
    $debug = Irssi::settings_get_bool("$IRSSI{name}_debug");

    %monitored_channels = ();
    %monitored_channels =
      map {
        my ( $chatnet, $channel ) = split /:/, $_, 2;
        lc($chatnet) => { lc($channel) => 1 };
      }
      split ' ', Irssi::settings_get_str("$IRSSI{name}_channels");

    # leave in ms for timeout_add
    $reop_check_delay = Irssi::settings_get_time("$IRSSI{name}_reop_check_delay");

    # convert from ms to seconds for epoch comparisions
    $max_cache_age = Irssi::settings_get_time("$IRSSI{name}_max_cache_age") / 1000;

    # leave in ms for timeout_add
    $expire_cache_period = Irssi::settings_get_time("$IRSSI{name}_expire_cache_period");
    if ( defined $expire_cache_timer_id )
    {
        Irssi::timeout_remove($expire_cache_timer_id);
    }
    $expire_cache_timer_id = Irssi::timeout_add( $expire_cache_period, 'expire_cache', undef );
}

Irssi::settings_add_str( $IRSSI{name}, "$IRSSI{name}_channels", "" );
Irssi::settings_add_time( $IRSSI{name}, "$IRSSI{name}_reop_check_delay", "10s" );
Irssi::settings_add_bool( $IRSSI{name}, "$IRSSI{name}_debug", 0 );
Irssi::settings_add_time( $IRSSI{name}, "$IRSSI{name}_max_cache_age",       "24h" );
Irssi::settings_add_time( $IRSSI{name}, "$IRSSI{name}_expire_cache_period", "1h" );
get_settings();

Irssi::signal_add_first(
    {
        'redir deoperit_userhost'         => \&event_redir_userhost,
        'redir deoperit_userhost_timeout' => \&event_redir_userhost_timeout,
        'nick mode changed'               => \&event_nick_mode,
        'message join'                    => \&event_join,
    }
);

Irssi::signal_add_last( { 'setup changed' => \&get_settings, } );

Irssi::print( sprintf( "Loaded %s v%s...", $IRSSI{'name'}, $VERSION ) );

