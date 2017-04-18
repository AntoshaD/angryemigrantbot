#!/usr/bin/env perl
use strict;
use warnings;
use WWW::Telegram::BotAPI;
use List::Util qw(shuffle);
use Data::Dumper;
use utf8;
use Encode;

open AU, "authtoken" or die; chomp(my $token = <AU>); close AU;

$| = 1;
my $api = WWW::Telegram::BotAPI->new(token => $token);

$api->agent->can("inactivity_timeout") and $api->agent->inactivity_timeout(45);
my $me = $api->getMe or die;
my ($offset, $updates) = 0;
my $lastpic;

my (@phr, @pic, @bingo);
my ($citecache, $piccache, $bingopos);

sub reload() {
	open UH, "unhappyemigrant.txt" or die; chomp(@phr = <UH>); close UH;
	open PI, "unhappyemigrant.pic" or die; chomp(@pic = <PI>); close PI;
	open BN, "unhappyemigrant.bng" or die; chomp(@bingo = <BN>); close BN;
	return (scalar(@phr), scalar(@pic), scalar(@bingo));
}

sub getCite($) {
	my $message = shift;
	my $from = $message->{from};
	my $id = $message->{chat}{id} || 'u' . $from->{id};
	$citecache->{$id} = { pos => 0, cites => [ shuffle(0..$#phr) ] } if !$citecache->{$id} || $citecache->{$id}->{pos} > $#phr;
	my $eprob = rand(100);
	my $ending = '.';
	if($eprob < 0.5) { $ending = join '', map { ["!", "1"]->[int rand 2] x (2 + int rand 5) } (0..2 + int rand 3) }
	elsif($eprob < 2) { $ending = '!!!'; }
	elsif($eprob < 10) { $ending = '!'; }
	elsif($eprob < 20) { $ending = '...'; }
	elsif($eprob < 30) { $ending = ', ' . ($from->{username} ? '@' . $from->{username} : join ' ', $from->{first_name}, $from->{last_name}) }
	return decode('utf8', $phr[$citecache->{$id}->{cites}->[$citecache->{$id}->{pos}++]]) . $ending;
}

sub getPic($) {
	my $message = shift;
	my $id = $message->{chat}{id} || 'u' . $message->{from}{id};
	$piccache->{$id} = { pos => 0, pics => [ shuffle(0..$#pic) ] } if !$piccache->{$id} || $piccache->{$id}->{pos} > $#pic;
	return { method => 'sendPhoto', photo => $pic[$piccache->{$id}->{pics}->[$piccache->{$id}->{pos}++]] };
}

sub getBingo($) {
	my $message = shift;
	my $id = $message->{chat}{id} || 'u' . $message->{from}{id};
	$bingopos->{$id} = 0 if !$bingopos->{$id} || $bingopos->{$id} > $#bingo;
	return { method => 'sendPhoto', photo => $bingo[$bingopos->{$id}++] };
}

my $commands = {
	"start" => "Привет, тракторист! Шлёпни меня командой /smack",
	"smack" => sub { rand(100) < 10 ? getPic(shift) : getCite(shift) },
	"changelog" => sub { open CH, 'ChangeLog'; chomp(my @cl = <CH>); close CH; join "\n", @cl; },
	"lastpic" => sub { $lastpic || "Ничего нет :'(" },
	"pic" => sub { getPic(shift) },
	"bingo" => sub { getBingo(shift) },
	"reload" => sub {
		return "Шалунишка!" unless $_[1] eq $token;
		my @r = reload;
		$citecache = $piccache = $bingopos = undef;
		return "$r[0] phrases, $r[1] pictures, $r[2] bingoes";
	},
	"_unknown" => "Unknown command :( Try /start"
};

printf "Hello! I am %s. Starting...\n", $me->{result}{username};
reload();

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
			for(my $i = 0; $i < ($method eq 'sendPhoto' ? 2 + int rand 3 : length(ref $res ? $res->{text} : $res) / 18) + 1; $i++) {
				sleep(1);
				eval {
					$api->sendChatAction({
						chat_id => $u->{message}{chat}{id},
						action => $method eq 'sendPhoto' ? 'upload_photo' : 'typing'
					});
				};
			}
			eval {
				$api->$method({
					chat_id => $u->{message}{chat}{id},
					$is_cmd ? () : (reply_to_message_id => $u->{message}->{message_id}),
					ref $res ? %$res : (text => $res),
				});
			};
			print "Reply sent.\n" unless $@;
		}
		if($u->{message}{photo}) {
			$lastpic = $u->{message}{photo}[0]{file_id};
		}
	}
}
