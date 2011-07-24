# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is proxy_away.pl
#
# The Initial Developer of the Original Code is the Ryan Tilder.
# Portions created by the Initial Developer are Copyright (C) 2010
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Ryan Tilder (ryan@tilder.org)
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 2 or later (the "GPL"), or
# the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
# in which case the provisions of the GPL or the LGPL are applicable instead
# of those above. If you wish to allow use of your version of this file only
# under the terms of either the GPL or the LGPL, and not to allow others to
# use your version of this file under the terms of the MPL, indicate your
# decision by deleting the provisions above and replace them with the notice
# and other provisions required by the GPL or the LGPL. If you do not delete
# the provisions above, a recipient may use your version of this file under
# the terms of any one of the MPL, the GPL or the LGPL.
#
# ***** END LICENSE BLOCK *****


use Irssi;

use vars qw($VERSION %IRSSI);

$VERSION = "0.0.1";
%IRSSI = (
    authors         => "Ryan Tilder",
    contact         => 'ryan@tilder.org',
    name            => "proxy_away",
    url             => "",
    description     => "When all proxy clients disconnect, set away",
    license         => "GPL",
    changed         => "2011-07-22"
);

my $PROXIES = {};

Irssi::settings_add_bool('misc', 'proxy_away_active', 1);
Irssi::settings_add_bool('misc', 'proxy_away_debug', 0);
Irssi::settings_add_str('misc', 'proxy_away_nick_addendum', '|detached');
Irssi::settings_add_str('misc', 'proxy_away_message', 'proxy client detached');
Irssi::settings_add_str('misc', 'proxy_away_ignored_nets', '');

# At load time, we store some state based on the list of servers that are proxied
my $ports = Irssi::settings_get_str('irssiproxy_ports');

if (not $ports) {
    Irssi::print('No proxy ports configured.');
}
else {
    get_proxies();
}

sub _debug {
    if (Irssi::settings_get_bool('proxy_away_debug')) {
        Irssi::print(shift);
    }
}

sub get_proxies {
    my $ports = Irssi::settings_get_str('irssiproxy_ports');

    my $ignored = [split(/\s+/,
                   Irssi::settings_get_str('proxy_away_ignored_nets'))];
    $ignored = { map {$_ => 1} @{$ignored} };

    foreach my $hostport (split(/\s+/, $ports)) {
        my ($proxy, undef) = split(/=/, $hostport);
        unless (exists($PROXIES->{$proxy})) {
            $PROXIES->{$proxy} = { client_count => 0, nick => undef,
                                   ignored => undef };
        }
        $PROXIES->{$proxy}->{'nick'} = Irssi::chatnet_find($proxy)->{'nick'};
        $PROXIES->{$proxy}->{'ignored'} = exists($ignored->{$proxy});
    }
}

sub client_connect {
    unless ($ports or Irssi::settings_get_str('proxy_away_active')) {
        _debug("proxy_away: no ports defined or proxy_away inactive.");
        return 0;
    }

    my $client = shift @_;
    my $server = $client->{'server'};

    # Make sure our list of proxies is up to date
    unless (exists($PROXIES->{$server->{'chatnet'}})) {
        get_proxies();
    }
    my $proxy = $PROXIES->{$server->{'chatnet'}};

    if ($proxy->{'ignored'}) {
        _debug("proxy_away: ignoring chat net \"$server->{'chatnet'}\"");
        return 0;
    }

    $proxy->{'client_count'}--;

    unless ($server->{'connected'}) {
        _debug("proxy_away: \"$server->{'real_address'}\" not connected.");
        return 0;
    }

    my $pa_msg = Irssi::settings_get_str('proxy_away_message');
    my $pa_nick_add = Irssi::settings_get_str('proxy_away_nick_addendum');

    unless ($server->{'usermode_away'}) {
        _debug("proxy_away: user isn't away on this server");
        return 0;
    }

    #unless ($server->{'away_reason'} eq $pa_msg
    #        and $server->{'nick'} =~ /$pa_nick_add$/) {
    #    _debug("proxy_away: nick or away message don't match.");
    #    return 0;
    #}

    # proxy_away is active, the nick and away message match that specified in
    # settings.  We revert our tweaks.
    $server->command('AWAY -one');
    $server->command("NICK $proxy->{'nick'}");

    _debug("proxy_away: reset nick to \"$proxy->{'nick'}\" and unset away.");

    return 0;
}

sub client_disconnect {
    unless ($ports or Irssi::settings_get_str('proxy_away_active')) {
        _debug("proxy_away: no ports defined or proxy_away inactive.");
        return 0;
    }

    my $client = shift @_;
    my $server = $client->{'server'};

    # Make sure our list of proxies is up to date
    unless (exists($PROXIES->{$server->{'chatnet'}})) {
        get_proxies();
    }
    my $proxy = $PROXIES->{$server->{'chatnet'}};

    if ($proxy->{'ignored'}) {
        _debug("proxy_away: ignoring chat net \"$server->{'chatnet'}\"");
        return 0;
    }

    $proxy->{'client_count'}--;

    unless ($server->{'connected'}) {
        _debug("proxy_away: \"$server->{'real_address'}\" not connected.");
        return 0;
    }

    # Client still connected?  Just return.
    if ($proxy->{'client_count'} > 0) {
        _debug("proxy_away: additional clients connected. No changes.");
        return 0;
    }

    unless ($server->{'usermode_away'}) {
        my $pa_msg = Irssi::settings_get_str('proxy_away_message');
        my $pa_nick_add = Irssi::settings_get_str('proxy_away_nick_addendum');
        my $newnick = $proxy->{'nick'} . $pa_nick_add;

        $server->command("AWAY -one $pa_msg");

        _debug("proxy_away: set away msg to $server->{'away_reason'}");

        unless ($server->{'nick'} eq $newnick) { 
            $server->command("NICK $newnick");
        }

        _debug("proxy_away: changed nick to \"$newnick\"");
    }

    return 0;
}

Irssi::signal_add('proxy client connected', \&client_connect); 
Irssi::signal_add('proxy client disconnected', \&client_disconnect); 
