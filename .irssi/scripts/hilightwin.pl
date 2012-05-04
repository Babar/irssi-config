#
# Print hilighted messages & private messages to window named "hilight" for
# irssi 0.7.99 by Timo Sirainen
#
# Modded a tiny bit by znx to stop private messages entering the hilighted
# window (can be toggled) and to put up a timestamp.
#
# Babar modded it a bit too:
# Added the timestamp from the theme, not default one
# Added send-notify support:
# After suggestion from tomaw, added remote notification support as explained
# on this blog post: http://blog.foosion.org/2008/02/15/libnotify-over-ssh/
# You'd have to configure your terminal for it, for example for urxvt:
# URxvt.print-pipe: ~/scripts/unmarshal.pl
# And put the umarshal.pl script in it, so:
# wget -qO ~/scripts/unmarshal.pl http://www.0x11.net/notify-remote/unmarshal.pl
# chmod 755 ~/scripts/unmarshal.pl

use Irssi;
use POSIX;
use vars qw($VERSION %IRSSI);

$VERSION = "0.03";
%IRSSI   = (
    authors     => "Timo \'cras\' Sirainen, Mark \'znx\' Sangster",
    contact     => "tss\@iki.fi, znxster\@gmail.com",
    name        => "hilightwin",
    description => "Print hilighted messages to window named \"hilight\"",
    license     => "Public Domain",
    url         => "http://irssi.org/",
    changed     => "Sun May 25 18:59:57 BST 2008"
);

sub sig_printtext {
    my ( $dest, $text, $stripped ) = @_;

    my $opt = MSGLEVEL_HILIGHT;

    if ( Irssi::settings_get_bool('hilightwin_showprivmsg') ) {
        $opt = MSGLEVEL_HILIGHT | MSGLEVEL_MSGS;
    }

    if (   ( $dest->{level} & ($opt) )
        && ( $dest->{level} & MSGLEVEL_NOHILIGHT ) == 0 )
    {
        $window = Irssi::window_find_name('hilight');

        system "/usr/bin/notify-send", $dest->{target}, $stripped
          if Irssi::settings_get_bool('hilightwin_sendnotify');
        if ( $dest->{level} & MSGLEVEL_PUBLIC ) {
            $text = $dest->{target} . ": " . $text;
        }
        my $theme = Irssi::current_theme();
        my $format =
          $theme->format_expand(
            $theme->get_format( 'fe-common/core', 'timestamp' ) );
        $format =~ s/\%(.)/$1 eq '%' ? '%' : "%%$1"/eg;
        $text   =~ s/\%/\%\%/g;
        $text = strftime( $format, localtime ) . $text;
        $window->print( $text, MSGLEVEL_NEVER ) if ($window);
    }
}

$window = Irssi::window_find_name('hilight');
Irssi::print("Create a window named 'hilight'") if ( !$window );

Irssi::settings_add_bool( 'hilightwin', 'hilightwin_showprivmsg', 1 );
Irssi::settings_add_bool( 'hilightwin', 'hilightwin_sendnotify',  0 );

Irssi::signal_add( 'print text', 'sig_printtext' );

# vim:set ts=4 sw=4 et:
