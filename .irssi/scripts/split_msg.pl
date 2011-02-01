# by Olivier 'Babar' Raginel <babar@magicnet.org>

use strict;

use vars qw($VERSION %IRSSI);
$VERSION = "20071221";
%IRSSI = (
    authors     => "Olivier 'Babar' Raginel",
    contact     => "babar\@magicnet.org",
    name        => "split_msg",
    description => "Split msgs sent to multiple nicks so they end up in the right window",
    license     => "GPLv2",
    changed     => "$VERSION",
    commands     => "msg"
);

use Irssi;

sub cmd_msg () {
    my ($line, $server) = @_;
    if ($line =~ /^(\S+) (.*)$/) {
	my ($targets, $msg) = ($1,$2);
	return unless $targets =~ /,/;
	$server->command("MSG $_ $msg") for split /,/, $targets;
	Irssi::signal_stop();
    }
}

Irssi::command_bind('msg', \&cmd_msg);
