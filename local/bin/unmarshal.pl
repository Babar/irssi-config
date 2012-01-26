#!/usr/bin/perl -wTCSDL
# http://www.0x11.net/notify-remote/unmarshal.pl
#
# see also my blog post on
# http://blog.foosion.org/2008/02/15/libnotify-over-ssh/
#
# based and inspired on
# http://jaredquinn.info/it-related/technical/unix/2007.09.25/libnotify-with-irssi-over-ssh/

use strict;
use warnings;
use utf8;
use MIME::QuotedPrint;
$ENV{PATH} = '/bin:/usr/bin';

my $icon     = "gtk-dialog-info";
my $timeout  = 5000;
my $urgency  = "normal";
my $content  = "";
my $category = "Message";
my $subject  = "";

sub unmarshall {
    my $string = decode_qp( $_[0] );
    for ($string) {
        s/=\\n$//;
        s/\\\\/\\/g;
        s/\\n/\n/g;

        s/&/&amp;/g;
        s/'/&apos;/g;
        s/"/&quot;/g;
        s/>/&gt;/g;
        s/</&lt;/g;
    }
    return $string;
}

while (<STDIN>) {
    if (/^([A-Z]+)\s+(.+?)\s*$/) {
        $category = unmarshall($2) if ( $1 eq 'CATEGORY' );
        $icon     = unmarshall($2) if ( $1 eq 'ICON' );
        $content  = unmarshall($2) if ( $1 eq 'CONTENT' );
        $timeout  = unmarshall($2) if ( $1 eq 'TIMEOUT' );
        $subject  = unmarshall($2) if ( $1 eq 'SUBJECT' );
        $urgency  = unmarshall($2) if ( $1 eq 'URGENCY' );
    }
}

exit unless ( $content or $subject );

system(
    'notify-send', '-i', $icon,    '-c', $category, '-u',
    $urgency,      '-t', $timeout, '--', $subject,  $content
);
