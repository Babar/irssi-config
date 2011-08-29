#!/usr/bin/perl -wT
# http://www.0x11.net/notify-remote/unmarshal.pl
#
# see also my blog post on
# http://blog.foosion.org/2008/02/15/libnotify-over-ssh/
#
# based and inspired on
# http://jaredquinn.info/it-related/technical/unix/2007.09.25/libnotify-with-irssi-over-ssh/

use strict;
$ENV{PATH} = '/bin:/usr/bin';

my $icon = "gtk-dialog-info";
my $timeout = 5000;
my $urgency = "normal";
my $content = "";
my $category = "Message";
my $subject = "";

sub unmarshall(\$)
{
	my $foo = shift;

	${$foo} =~ s/\\\\/\\/g;
	${$foo} =~ s/\\n/\n/g;

	# escape it as well
	${$foo} =~ s/&/&amp;/g;
	${$foo} =~ s/'/&apos;/g;
	${$foo} =~ s/"/&quot;/g;
	${$foo} =~ s/>/&gt;/g;
	${$foo} =~ s/</&lt;/g;
}

while (<STDIN>)
{
	if (/^([A-Z]+)\s+(.+?)\s*$/)
	{
		$category = $2 if ($1 eq 'CATEGORY');
		$icon     = $2 if ($1 eq 'ICON');
		$content  = $2 if ($1 eq 'CONTENT');
		$timeout  = $2 if ($1 eq 'TIMEOUT');
		$subject  = $2 if ($1 eq 'SUBJECT');
		$urgency  = $2 if ($1 eq 'URGENCY');
	}
}

exit unless ($content or $subject);

unmarshall($category);
unmarshall($icon);
unmarshall($content);
unmarshall($timeout);
unmarshall($subject);
unmarshall($urgency);

system('notify-send', '-i', $icon, '-c', $category, '-u', $urgency, '-t', $timeout, '--', $subject, $content);
