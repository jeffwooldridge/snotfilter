#!/usr/bin/perl

use warnings;
use strict;

################################################################################
#                                                                              #
#  snot-filter.pl - xchat filter and oper communication script for UnrealdIRCd #
#  users. Helpop ChatOps GlobOps NaChat AdChat LocOps.                         #
#                                                                              #
#  Copyright (C) 2008, 2009 Sergio Luis <sergio at 0xffffff.org>               #
#                           Jeff Wooldridge <jefferoos at gmail.com>           #
#                                                                              #
#  snot-filer.pl is free software; you can redistribute it and/or modify       #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation; either version 2 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  snot-filter.pl is distributed in the hope that it will be useful,           #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program; if not, write to the Free Software                 #
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA  #
#                                                                              #
################################################################################


# Many credits goes to Sergio, and MCM for their help and support.

my $script = "Snot-Filter";
my $version = "007";
my $desc = "Server Notice Filter and other stuff";

Xchat::register($script, $version, $desc, \&unload);

my $server_notice_hook = Xchat::hook_server("NOTICE", \&server_notice_handler);

# hooking any non-command
Xchat::hook_command("", \&non_command_handler);

Xchat::hook_command("me", \&non_command_handler);
Xchat::hook_command("notinchan", \&not_in_chan);
Xchat::hook_command("who", \&who_command_handler);

Xchat::hook_print("Part", \&eat_parts_from_clients);
Xchat::hook_print("Change Nick", \&eat_quit_on_tab);
Xchat::hook_print("Quit", \&eat_quit_on_tab);
Xchat::hook_print("Users On Channel", \&eat_quit_on_tab);

# Used to block annoying errors when fake rooms are created and used.
Xchat::hook_server("401", \&block_raws);
Xchat::hook_server("403", \&block_raws);
Xchat::hook_server("334", \&block_raws);

# If you are a non-oper but recieve helpop messages change the %global_settings to 
#  who => "#help", cb => \&helpop_who_handler,

# if you are an oper using -HelpOp change your helpop hash too...
#  who => "+m-m h S", cb => \&std_who_handler,


my %global_settings =
(
	helpop => {identifier => "HelpOp", tab => "-HelpOp", command => "helpop", who => "+m-m h S", cb => \&std_who_handler,},
	chatops => {identifier => "ChatOps", tab => "-ChatOps", command => "chatops", who => "+m-m oO S", cb => \&std_who_handler,},
	nachat => {identifier => "NetAdmin.Chat", tab => "-NAChat", command => "nachat", who => "+m-m N S", cb => \&std_who_handler,},
	locops => {identifier => "LocOps", tab => "-LocOps", command => "locops", who => "+m-m o S", cb => \&std_who_handler,},
	global => {identifier => "Global", tab => "-GlobOps", command => "globops", who => "+m-m Oo S", cb => \&std_who_handler,},
	adchat => {identifier => "AdminChat", tab => "-AdChat", command => "adchat", who => "+m-m aA S", cb => \&std_who_handler,},
	clients => {identifier => "Client", tab => "-Clients", who => "+n \*", cb => \&std_who_handler,},
	idle => {tab => "-NotInChan", who => "+i \*", cb => \&idle_who_handler,},
);

my %colors =
(
	"light grey" => "00",
	"black" => "01",
	"dark blue" => "02",
	"dark green" => "03",
	"red" => "04",
	"purple" => "06",
	"brown" => "07",
	"orange" => "08",
	"green" => "09",
	"cyan" => "10",
	"light green" => "11",
	"blue" => "12",
	"pink" => "13",
	"dark grey" => "14",
	"grey" => "15",
	"default" => "01"
);

my $nicks_tab = "-NickChange";
my $globals_tab = "-Global";
my $services_tab = "-Services";
my $kills_tab = "-Kills";
my $bans_tab = "-Bans";
my $whois_tab = "-Whois";

my %whoTimer;

sub bold($)
{
	my $text = shift;

	return "\cB" . $text . "\cO";
}

sub color($$)
{
	my ($text, $color) = @_;

	my $mapped_color = exists($colors{$color}) ? $colors{$color} : $colors{default};

	return "\cC" . $mapped_color . $text . "\cO";
}

# this routine deals with the notices received from the server. in our case, we are interested
# in helpop/chatops notices
sub server_notice_handler($) 
{
	# Prevents certain server messages and regular Notices
	if ($_[0][0] eq "NOTICE" || $_[0][2] eq "AUTH" || $_[0][0] =~ /!/ || !defined($_[0][3]))
	{
		return Xchat::EAT_NONE;
	}

	my $notice = $_[1][3];

	if ($notice =~ /^:\*\*\* Notice -- (Client) (exiting|connecting)/)
	{
		my $identifier = $1;
		my $type = $2;
		my ($nick, $ident, $host, $quit, $server, $remote, $port, $text);

		my $settings = &get_settings_by_key("identifier", $identifier);
		return Xchat::EAT_NONE if not defined($settings);

		my $currentServer = Xchat::get_info('server'); 
		my $yourNickname = $_[0][2];

		# Creates a new tab if not found
		unless(Xchat::find_context($settings->{tab}, $currentServer))
		{
			Xchat::command("recv :$yourNickname\!blah\@blah.net JOIN :$settings->{tab}");
			Xchat::command("timer 10 who ". $settings->{who});
		}

		if ($type eq "exiting")
		{
			if ($notice =~ /Client exiting(:| at (.*?):) ((.*?)\!(.*?)\@(.*?) \((Quit: )?(.*?)\)|(.*?) \((.*?)\@(.*?)\) \[(Quit: )?(.*?)\])/)
			{
				if ($1 eq ":")
				{
					$nick = $9;
					$ident = $10;
					$host = $11;
					$quit = (defined($12) ? $12 : "") . $13;
					$server = Xchat::get_info("server");
					$remote = 0;
				}
				else
				{
					$nick = $4;
					$ident = $5;
					$host = $6;
					$quit = (defined($7) ? $7 : "") .  $8;
					$server = $2;
					$remote = 1;
				}

				$text = &bold($nick) . " ($ident\@$host) " . &bold($server) . " ($quit)";
				&on_client_tab($currentServer, $settings->{tab}, &bold(&color("-", "red")), "$text");
				&remove_from_special_tabs($nick, "$nick\!$ident\@$host", $quit);
			}
			else
			{
				Xchat::print('something strange happened here... notice: [$notice]');
			}
		}
		else
		{
			# connecting
			if ($notice =~ /Client connecting ((on port (\d+?))|(at (.*?))): (.*?) \((.*?)\@(.*?)\)/)
			{
				$nick = $6;
				$ident = $7;
				$host = $8;
	
				if (defined($2))
				{
					$remote = 0;
					$port = $3;
					$server = Xchat::get_info("server");
				}
				else
				{
					$remote = 1;
					$port = "unavailable (remote server)";
					$server = $5;
				}

				$text = &bold($nick) . " ($ident\@$host) " . &bold($server) . ", port $port";
				&on_client_tab($currentServer, $settings->{tab}, &bold(&color("+", "dark green")), "$text");
				Xchat::command("recv :$currentServer 353 $yourNickname = $settings->{tab} :$yourNickname $nick");
			}
			else
			{
				Xchat::print('something strange happened here... notice: [$notice]');
			}
		}
	}

	# Services and network related notices
	elsif ($notice =~ s/^\:\*\*\* Global \-\- from (\w+Serv|.*\.[a-zA-Z]{2,3}|collision): //)
	{
		my $nickname = $1;
		if ($nickname eq "OperServ" && $notice =~ /^.* add an AKILL /)
		{
			&print_to_query($bans_tab, $nickname, $notice);
		}
		else
		{
			&print_to_query($services_tab, $nickname, $notice);
		}
	}

	# Captures numerous forms of Oper communication through Server Notices (Unreal IRCd)
	elsif ($notice =~ /^:\*\*\* (HelpOp|ChatOps|LocOps|Global|NetAdmin.Chat|AdminChat) \-\- from (.*?)(?: \(HelpOp\):|:)\s(.*)$/) 
	{
		my $identifier = $1;
		my $nick = $2;
		my $text = $3;

		my $settings = &get_settings_by_key("identifier", $identifier);
		return Xchat::EAT_NONE if not defined($settings);

		my $currentServer = Xchat::get_info('server');
		my $yourNickname = $_[0][2];

		unless(Xchat::find_context($settings->{tab}, $currentServer)) 
		{
			Xchat::command("recv :$yourNickname\!blah\@blah.net JOIN :$settings->{tab}");
			Xchat::command("timer 5 who ". $settings->{who});
		}

		Xchat::set_context($settings->{tab}, $currentServer);
		&emit_print_handler($nick, $text);
	}

	elsif ($notice =~ /^:\*\*\* Notice \-\- (.*?) \((.*?)\) has (?:changed his\/her nickname|been forced to change his\/her nickname) to\s(.*)/)
	{
		my $nickname = $1;
		my $hostaddress = $2;
		my $nickchange = $3;

		Xchat::command("RECV :$nickname!$hostaddress NICK :$nickchange"); # changes nicks on userlists

		&print_to_query($nicks_tab, $nickname, "is now \cB$nickchange\cO  $hostaddress");
	}

	elsif ($_[0][3] =~ /^:(Stats|Forbidding|Failed|\[Spamfilter\])$/)
	{
		my $type = &bold($1);
		&print_to_query($globals_tab, $type, $_[1][4]);
	}

	elsif ($_[0][4] =~ /^(?:OperOverride|Flood|Spamfilter)$/)
	{
		&print_to_query($globals_tab, $_[0][4], $_[1][5]);
	}

	elsif ($notice =~ s/^:(.*?) (Link|Secure) //)
	{
		my $msgType = $1;
		my $netType = $2;

		&print_to_query($globals_tab, $msgType, "$netType $notice");
	}

	elsif ($notice =~ s/^:\*\*\* (Permanent|Expiring) ((?:Global\s)?.*?)\s//)
	{
		my $msgType = &bold($1);
		my $banType = &bold($2);

		&print_to_query($bans_tab, $msgType, "$banType $notice");
	}

	elsif ($notice =~ s/^:\*\*\* ((?:Global\s)?.*?) added for //)
	{
		my $banType = &bold($1);
		my $msgType = &bold(&color("Added", "red"));
		
		&print_to_query($bans_tab, $msgType, "$banType $notice");
	}

	elsif ($notice =~ /^:(.*?)\!(.*?) removed ((?:Global\s)?.*?) (.*?) \((.*?)\)/)
	{
		my $remover = $1;
		my $removerHost = $2;
		my $banType = $3;
		my $ban = $4;
		my $when = $5;
		my $msgType = &bold(&color("Removed", "light green"));
		
		&print_to_query($bans_tab, $msgType, "$banType $ban from $remover $removerHost $when");
	}	

	elsif ("is" eq $_[0][6] && "now" eq $_[0][7]) # Opered Up
	{
		if (&check_time(Xchat::get_info("network")) == 1)
		{
			&update_userlists();
		}

		$notice =~ s/^:(.*) /$1 /;
		&print_to_query($globals_tab, "\cBOper", $notice);
	}

	elsif ("did a /whois on you." eq $_[1][6]) # whois
	{
		&print_to_query($whois_tab, $_[0][4], $_[1][5]);
	}

	elsif ("KILL" eq $_[0][7]) # Kills
	{
		&print_to_query($bans_tab, "\002Kill", $_[1][8]);
	}

	else
	{
		return Xchat::EAT_NONE;
	}

	return Xchat::EAT_XCHAT;
}


sub check_time($)
{
	my $network = shift;

	if (!exists($whoTimer{$network}) || !exists($whoTimer{$network}{begin}))
	{
		$whoTimer{$network}{begin} = time();

		return 1;
	}

	$whoTimer{$network}{ending} = time();
	
	$whoTimer{$network}{diff} = $whoTimer{$network}{ending} - $whoTimer{$network}{begin};
	
	$whoTimer{$network}{begin} = time();

	if ($whoTimer{$network}{diff} > 3.0) # ok to go..
	{
		return 1;
	}

	return 0;
}


sub on_client_tab($)
{
	my ($server, $tab, $nick, $text) = @_;

	Xchat::set_context($tab, $server);
	Xchat::emit_print("Channel Message", $nick, $text);
}

sub print_to_query($)
{
	my ($tab, $nick, $text) = @_;

	my $server = Xchat::get_info('server');

	unless (Xchat::find_context($tab, $server)) 
	{
		Xchat::command("query -nofocus " . $tab);
	}

	Xchat::set_context($tab, $server);
	Xchat::emit_print("Channel Message", $nick, $text);
}


# blocks some annoying servernotices after creation of fake channels
sub block_raws
{
	my $server = Xchat::get_info("server");

	foreach my $key (keys %global_settings)
	{
		if (defined($global_settings{$key}->{tab}) &&
			Xchat::find_context($global_settings{$key}->{tab}, $server))
		{
			return Xchat::EAT_ALL;
		}
	}

	return Xchat::EAT_NONE;
}


####################################################
# Uses Xchat Settings to properly print messages.  #
####################################################
sub emit_print_handler 
{
	my $nick = shift;
	my $text = shift;
	my $mynick = Xchat::get_info("nick");
	
	if ($text =~ s/^me\s//)
	{
		if ($nick eq $mynick)
		{
			Xchat::emit_print("Your Action", $nick, $text);
			Xchat::command("GUI COLOR 2");
		}
		elsif ((&is_hilight($text) && &not_to_hilight($nick)) || &always_hilight($nick))
		{
			Xchat::emit_print("Channel Action Hilight", $nick, $text);
			Xchat::command("GUI COLOR 3");
		}
		else 
		{
			Xchat::emit_print("Channel Action", $nick, $text);
			Xchat::command("GUI COLOR 2");
		}
	}
	else
	{
		if ($nick eq $mynick)
		{
			Xchat::emit_print("Your Message", $nick, $text);
			Xchat::command("GUI COLOR 2");
		}
		elsif ((&is_hilight($text) && &not_to_hilight($nick)) || &always_hilight($nick)) 
		{
			Xchat::emit_print("Channel Msg Hilight", $nick, $text);
			Xchat::command("GUI COLOR 3");
		}
		else
		{
			Xchat::emit_print("Channel Message", $nick, $text);
			Xchat::command("GUI COLOR 2");
		}
	}
}

sub is_hilight($)
{
	my $text = shift;

	Xchat::strip_code($text);

	my $list = Xchat::get_prefs("irc_extra_hilight");
	my @words = split(/,/, $list);

	$words[++$#words] = Xchat::get_info("nick");

	for (my $i = 0; $i <= $#words; $i++)
	{
		my $found_match = index($text, $words[$i]);
		return 1 if ($found_match >= 0);
	}

	return undef;
}

sub not_to_hilight($)
{
	my $nick = shift;

	Xchat::strip_code($nick);

	my $list = Xchat::get_prefs("irc_no_hilight");
	my @ignored_nicks = split(/,/, $list);

	$ignored_nicks[++$#ignored_nicks] = Xchat::get_info("nick");

	for (my $i = 0; $i <= $#ignored_nicks; $i++)
	{
		return undef if ($ignored_nicks[$i] eq $nick);
	}

	return 1;
}

sub always_hilight
{
	my $nick = shift;

	Xchat::strip_code($nick);

	my $list = Xchat::get_prefs("irc_nick_hilight");
	my @hilight_nicks = split(/,/, $list);

	for (my $i = 0; $i <= $#hilight_nicks; $i++) 
	{
		return 1 if ($hilight_nicks[$i] eq $nick);
	}

	return undef;
}


# this routine deals with any non command. here we are interested in things typed inside the helper/chatops tab.
sub non_command_handler($$)
{
	my $text = shift(@{$_[1]});
	my $channel = Xchat::get_info("channel");

	my $settings = &get_settings_by_key("tab", $channel);
	return Xchat::EAT_NONE if not defined($settings);
	
	# checking whether we are in the helper/chatops tab
	if (lc($channel) eq lc($settings->{tab}))
	{
		Xchat::command($settings->{command} . " :" . $text);

		return Xchat::EAT_XCHAT;
	}

	return Xchat::EAT_NONE;
}


# Command "notinchan" basically the -IDLE tab
sub not_in_chan($)
{
	return Xchat::EAT_NONE if defined ($_[0][1]);

	my $server = Xchat::get_info('server');
	my $mynick = Xchat::get_info('nick');

	Xchat::command("recv :$mynick!blah\@blah.net JOIN :-NotInChan") unless Xchat::find_context("-NotInChan",$server);
	Xchat::command("timer 1 who +i \*");

	return Xchat::EAT_XCHAT;
}


# /Who command hooks for special rooms
my $hook = "";
my $unhook = "";

my @userlist = ();
my @userlist2 = ();
my @userlist3 = ();

my $what_tab; # Used to assure correct tabing.
my $what_server;


# Handles the who commands for the userlists.
sub who_command_handler($$)
{
	my $settings = &get_settings_by_key("who", $_[1][1]);
	return Xchat::EAT_NONE if not defined($settings);
	
	my $server = Xchat::get_info("server");

	if ($_[1][1] eq $settings->{who})
	{
		$what_tab = $settings->{tab};
		$what_server = Xchat::get_info("server");

		if ($hook)
		{
			Xchat::unhook($hook);
			$hook = "";
		}
		if($unhook)
		{
			Xchat::unhook($unhook);
			$unhook = "";
		}

		$hook =  Xchat::hook_server("352", $settings->{cb});
		$unhook = Xchat::hook_server("315", \&unhook);
	}

	return Xchat::EAT_NONE;
}


############################################################
#   These subroutines handle the data from the /who list   #
############################################################
sub std_who_handler($)
{
	if ($what_tab && $what_server && Xchat::find_context($what_tab, $what_server))
	{
		my $nick = $_[0][7];

		if ($#userlist < 400)
		{
			$userlist[++$#userlist] = $nick;
		}
		elsif (($#userlist + $#userlist2) < 800)
		{
			$userlist2[++$#userlist2] = $nick;
		}
		elsif (($#userlist + $#userlist2 + $#userlist3) < 1200)
		{
			$userlist3[++$#userlist3] = $nick;
		}
	}

	else
	{
		Xchat::print("what_tab = $what_tab what_server = $what_server");
	}

	return Xchat::EAT_XCHAT;
}


sub helpop_who_handler($)
{
	# Just checks channel prefixes of the specified room
	my $nick = $_[0][7];
	my $prefix = $_[0][8];

	if ($prefix =~ /\@|\%|\&/)
	{
		if ($#userlist < 400)
		{
			$userlist[++$#userlist] = $nick;
		}
	}

	return Xchat::EAT_XCHAT;
}


sub idle_who_handler($)
{
	# Checks if the user is in a room by the /who list!
	my $nick = $_[0][7];
	my $channel = $_[0][3];

	if ($channel !~ /^#/) # checks if there is a channel in the /who list
	{
		if ($#userlist < 400) 
		{
			$userlist[++$#userlist] = $nick;
		}
	}

	return Xchat::EAT_XCHAT;
}


# Unhooks created hooks
sub unhook
{
	my $mynick = Xchat::get_info("nick");
	my $server = Xchat::get_info("server");
	# Ends the hook of who list

	Xchat::unhook($hook);
	$hook = "";

	if (@userlist)
	{
		Xchat::command("recv :$server 353 $mynick = $what_tab :".join(' ', @userlist));
		@userlist = ();
	}
	if (@userlist2)
	{
		Xchat::command("recv :$server 353 $mynick = $what_tab :".join(' ', @userlist2));
		@userlist2 = ();
	}
	if (@userlist3)
	{
		Xchat::command("recv :$server 353 $mynick = $what_tab :".join(' ', @userlist3));
		@userlist3 = ();
	}
	#Xchat::print("recv :$server 353 $mynick = $what_tab :".$userlist);
	
	# Stops hook function of server code 315 aka End of /who list.
	# Unhooks this subroutine.
	Xchat::unhook($unhook);
	$unhook = "";

	return Xchat::EAT_XCHAT;
}



sub eat_parts_from_clients($)
{
	Xchat::print("aquiiiiii\n");
	my $channel = $_[0][2];
	Xchat::strip_code($channel);

	if ($channel eq "-Clients")
	{
		return Xchat::EAT_ALL;
	}

	return Xchat::EAT_NONE;
}


sub eat_quit_on_tab()
{
	my $channel = Xchat::get_info("channel");

	foreach my $key (keys %global_settings)
	{
		if (defined($global_settings{$key}->{tab}) && lc($global_settings{$key}->{tab}) eq lc($channel))
		{
			return Xchat::EAT_ALL;
		}
	}

	return Xchat::EAT_NONE;
}


sub eat_names_list($)
{
	my $tab = $_[0][0];
	Xchat::strip_code($tab);
	
	if ($tab =~ /^\-/)
	{
		return Xchat::EAT_ALL;
	}
	
	return Xchat::EAT_NONE;
}


# Handles the global hashes (Sergio made xD)
sub get_settings_by_key($)
{
	my ($type, $item) = @_;

	foreach my $key (keys %global_settings)
	{
		if (defined($type) && defined($item) && (defined($global_settings{$key}->{$type}) && ($global_settings{$key}->{$type} eq $item)))
		{
			return $global_settings{$key};
		}
	}
	return undef;
}


sub user_in_list($$)
{
	my ($nick, $channel) = @_;
	my $server = Xchat::get_info("server");

	my $context = Xchat::get_context();

	Xchat::set_context($channel, $server);
	my @users = Xchat::get_list("users");
	Xchat::set_context($context);


	foreach my $user (@users)
	{
		if (lc($user->{nick}) eq lc($nick))
		{
			return 1;
		}
	}

	return 0;
}


sub remove_from_special_tabs($$)
{
	my ($nick, $userid, $quit) = @_;

	Xchat::command("TIMER .5 RECV :$userid QUIT :$quit");
}


sub update_userlists
{
	Xchat::print("UpdateUserlists");
	my $server = Xchat::get_info("server");
	
	if (Xchat::find_context("-HelpOp", $server))
	{
		Xchat::command("who +m-m h S");
	}
	if (Xchat::find_context("-ChatOps", $server))
	{
		Xchat::command("timer 4 who +m-m oO S");
	}
	if (Xchat::find_context("-LocOps", $server))
	{
		Xchat::command("timer 8 who +m-m o S");
	}
	if (Xchat::find_context("-GlobOps", $server))
	{
		Xchat::command("timer 12 who +m-m Oo S");
	}
	if (Xchat::find_context("-AdChat", $server))
	{
		Xchat::command("timer 16 who +m-m aA S");
	}
	if (Xchat::find_context("-NAChat", $server))
	{
		Xchat::command("timer 20 who +m-m N S");
	}
}

sub unload
{
	Xchat::print("$script version $version unloaded!");
}

Xchat::print("\cB$script version $version loaded!");

