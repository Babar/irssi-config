$VERSION = "0.1";
%IRSSI = (
    authors     => "Jari Matilainen",
    contact     => "vague!#irssi@freenode",
    name        => "notifyquit",
    description => "Notify if user has left the channel",
    license     => "Public Domain",
    url         => "http://vague.se"
);

Irssi::signal_add_first("send text", sub {
  my ($data, $server, $witem) = @_;
  my $completion_char = Irssi::settings_get_str("completion_char");

  if($data =~ /^(\w+?)$completion_char/) {
    if(!$witem->nick_find($1)) {
      $witem->print("$1 has left the chat");
      Irssi::signal_stop();
    }
  }
});
