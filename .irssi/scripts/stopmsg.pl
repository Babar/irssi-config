#
# A simple script for Irssi that will stop you from sending messages to a
# selected channel.
#
# Copyright (C) 2011 Mark Sangster <znxster@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.
#
# Thanks go to the various scripts on http://scripts.irssi.org/
#

use Irssi;
use strict;
use vars qw($VERSION %IRSSI);

$VERSION = '0.1';
%IRSSI = (
	authors		=>	'Mark \'znx\' Sangster',
	contact		=>	'znxster@gmail.com',
	name		=>	'stopmsg.pl',
	description	=>	'Stop messages from sending to a particular channel',
	license		=>	'GPLv3',
	url			=>	'http://znx.no/'
);

# Sort out theme for various messages
Irssi::theme_register([
	'stopmsg_loaded', '%R>>%n %_stopmsg:%_ Version $0 by $1.',
]);

sub stopmsg_signal {
	my ($server, $msg, $target) = @_;
	if(channel_allowed($target)) {
		Irssi::signal_stop();
	}
}

# From piespy.pl
sub channel_allowed($) {
	my ($msgtarget) = @_;
	$msgtarget = lc $msgtarget;
	if(my $l = Irssi::settings_get_str("stopmsg_channels")) {
		return 1 if grep { lc $_ eq $msgtarget } split (/,/, $l)
	}
	return 0;
}

Irssi::signal_add('message own_public', 'stopmsg_signal');
Irssi::settings_add_str("stopmsg", "stopmsg_channels", "");
Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'stopmsg_loaded', $VERSION, $IRSSI{authors});
