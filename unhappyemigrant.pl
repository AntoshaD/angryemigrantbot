#!/usr/bin/env perl
use strict;
use warnings;
use WWW::Telegram::BotAPI;
use List::Util qw(shuffle);
use Data::Dumper;
use utf8;
use Encode;

open UH, "unhappyemigrant.txt" or die;
chomp(my @phr = <UH>);
close UH;

open AU, "authtoken" or die;
chomp(my $token = <AU>);
close AU;

$| = 1;
my $api = WWW::Telegram::BotAPI->new(token => $token);

$api->agent->can("inactivity_timeout") and $api->agent->inactivity_timeout(45);
my $me = $api->getMe or die;
my ($offset, $updates) = 0;

my $citecache;

sub getCite($) {
	my $message = shift;
	my $from = $message->{from};
	my $id = $message->{chat}{id} || 'u' . $from->{id};
	if(!$citecache->{$id} || $citecache->{$id}->{pos} > $#phr) {
		$citecache->{$id} = { pos => 0, cites => [ shuffle(0..$#phr) ] };
	}
	my $eprob = rand(100);
	my $ending = '.';
	if($eprob < 0.5) { $ending = join '', map { ["!", "1"]->[int rand 2] x (2 + int rand 5) } (0..2 + int rand 3) }
	elsif($eprob < 2) { $ending = '!!!'; }
	elsif($eprob < 10) { $ending = '!'; }
	elsif($eprob < 20) { $ending = '...'; }
	elsif($eprob < 30) { $ending = ', ' . ($from->{username} ? '@' . $from->{username} : join ' ', $from->{first_name}, $from->{last_name}) }
	return decode('utf8', $phr[$citecache->{$id}->{cites}->[$citecache->{$id}->{pos}++]]) . $ending;
}

my $commands = {
	"start" => "Привет, тракторист! Шлёпни меня командой /smack",
	"smack" => sub { getCite(shift) },
	"changelog" => sub { open CH, 'ChangeLog'; chomp(my @cl = <CH>); close CH; join "\n", @cl; },
	"_unknown" => "Unknown command :( Try /start"
};

printf "Hello! I am %s. Starting...\n", $me->{result}{username};

while(1) {
	$updates = $api->getUpdates({
		timeout => 5,
		$offset ? (offset => $offset) : ()
	});
	unless($updates and ref $updates eq "HASH" and $updates->{ok}) {
		warn "WARNING: getUpdates returned a false value - trying again...";
		next;
	}
	for my $u (@{$updates->{result}}) {
		$offset = $u->{update_id} + 1 if $u->{update_id} >= $offset;
		if(my $text = $u->{message}{text}) {
			printf "Incoming text message from \@%s\n", $u->{message}{from}{username};
			printf "Text: %s\n", $text;
			my $is_cmd = ($text =~ m|^/|);
			$text = '/smack' unless $text =~ m|^/[^_].|;
			my ($cmd, @params) = split / /, $text;
			$cmd =~ s/@.*//;
			my $res = $commands->{substr ($cmd, 1)} || $commands->{_unknown};
			$res = $res->($u->{message}, @params) if ref $res eq "CODE";
			next unless $res;
			my $method = ref $res && $res->{method} ? delete $res->{method} : "sendMessage";
			eval {
				$api->$method({
					chat_id => $u->{message}{chat}{id},
					$is_cmd ? () : (reply_to_message_id => $u->{message}->{message_id}),
					ref $res ? %$res : (text => $res),
				});
			};
			print "Reply sent.\n" unless $@;
		}
	}
}
