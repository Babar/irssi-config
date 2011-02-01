#!/usr/bin/perl -wCSDAL
## uniud.pl
# Eric Veldhuyzen
# Write messages upside down on the channel :)

use strict;
use utf8;
use PerlIO;

use vars qw($VERSION %IRSSI);

$VERSION = "2005063001";

%IRSSI = (
	authors		=>	"Eric Veldhuyzen",
	contact		=>	"eric\@terra.nu",
	name		=>	"uniud",
	description	=>	"Updside down encoding",
	license		=>	"GPLv2",
	changed		=>	"$VERSION",
	commands	=>	"uniud"
);

use Irssi 20020324;

my %updown = (
    ' ' => ' ',
    '!' => "\x{00a1}",
    '"' => "\x{201e}",
    '#' => '#',
    '$' => '$',
    '%' => '%',
    '&' => "\x{214b}",
    "'" => "\x{0375}",
    '(' => ')',
    ')' => '(',
    '*' => '*',
    '+' => '+',
    ',' => "\x{2018}",
    '-' => '-',
    '.' => "\x{02d9}",
    '/' => '/',
    '0' => '0',
    '1' => '1',
    '2' => '',
    '3' => '',
    '4' => '',
    '5' => "\x{1515}",
    '6' => '9',
    '7' => '',
    '8' => '8',
    '9' => '6',
    ':' => ':',
    ';' => "\x{22c5}\x{0315}",
    '<' => '>',
    '=' => '=',
    '>' => '<',
    '?' => "\x{00bf}",
    '@' => '@',
    'A' => "\x{13cc}",
    'B' => "\x{03f4}",
    'C' => "\x{0186}",
    'D' => 'p',
    'E' => "\x{018e}",
    'F' => "\x{2132}",
    'G' => "\x{2141}",
    'H' => 'H',
    'I' => 'I',
    'J' => "\x{017f}\x{0332}",
    'K' => "\x{029e}",
    'L' => "\x{2142}",
    'M' => "\x{019c}",
    'N' => 'N',
    'O' => 'O',
    'P' => 'd',
    'Q' => "\x{053e}",
    'R' => "\x{0222}",
    'S' => 'S',
    'T' => "\x{22a5}",
    'U' => "\x{144e}",
    'V' => "\x{039b}",
    'W' => 'M',
    'X' => 'X',
    'Y' => "\x{2144}",
    'Z' => 'Z',
    '[' => ']',
    '\\' => '\\',
    ']' => '[',
    '^' => "\x{203f}",
    '_' => "\x{203e}",
    '`' => "\x{0020}\x{0316}",
    'a' => "\x{0250}",
    'b' => 'q',
    'c' => "\x{0254}",
    'd' => 'p',
    'e' => "\x{01dd}",
    'f' => "\x{025f}",
    'g' => "\x{0253}",
    'h' => "\x{0265}",
    'i' => "\x{0131}\x{0323}",
    'j' => "\x{017f}\x{0323}",
    'k' => "\x{029e}",
    'l' => "\x{01ae}",
    'm' => "\x{026f}",
    'n' => 'u',
    'o' => 'o',
    'p' => 'd',
    'q' => 'b',
    'r' => "\x{0279}",
    's' => 's',
    't' => "\x{0287}",
    'u' => 'n',
    'v' => "\x{028c}",
    'w' => "\x{028d}",
    'x' => 'x',
    'y' => "\x{028e}",
    'z' => 'z',
    '{' => '}',
    '|' => '|',
    '}' => '{',
    '~' => "\x{223c}",
);
my $missing = "\x{fffd}"; # replacement character

sub uniud ($) {
    my $str = shift;
    my $turned = '';
    my $tlength = 0;

    for my $char ( $str =~ /(\X)/g ) {
        if ( exists $updown{$char} ) {
            my $t = $updown{$char};
            $t = $missing if !length($t);
            $turned = $t . $turned;
            $tlength++;
        } elsif ( $char eq "\t" ) {
            my $tablen = 8 - $tlength % 8;
            $turned = " " x $tablen . $turned;
            $tlength += $tablen;
        } elsif ( ord($char) >= 32 ) {
            ### other chars copied literally
            $turned = $char . $turned;
            $tlength++;
        }
    }
    return $turned . "  ";
}

sub cmd_uniud ($$$)
{
    my ($arg, $server, $witem) = @_;

    if ($witem &&
        ($witem->{type} eq 'CHANNEL' ||
         $witem->{type} eq 'QUERY')) {
        $witem->command('MSG '.$witem->{name}.' '.uniud($arg));
    } else {
        print CLIENTCRAP "%B>>%n ".uniud($arg);
    }
}

Irssi::command_bind('uniud',\&cmd_uniud);

print "%B>>%n ".$IRSSI{name}." ".$VERSION." loaded";
