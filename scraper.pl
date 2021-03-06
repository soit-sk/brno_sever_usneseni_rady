#!/usr/bin/env perl
# Copyright 2014-2015 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Digest::MD5;
use Encode qw(decode_utf8 encode_utf8);
use English;
use File::Temp qw(tempfile);
use HTML::TreeBuilder;
use LWP::UserAgent;
use POSIX qw(strftime);
use URI;
use Time::Local;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('http://www.sever.brno.cz/volene-organy-s/646-aktualni-usneseni-rady.html');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my $root = get_root($base_uri);

# Look for items.
my @tables = $root->find_by_tag_name('table');
foreach my $table (@tables) {
    my @tr = $table->find_by_tag_name('tr');
    foreach my $tr (@tr) {
        my ($date_td, $doc_td) = $tr->find_by_tag_name('td');
        my $date = get_db_date($date_td->as_text);
        my $doc_a = $doc_td->find_by_tag_name('a');

        # Save.
        if ($doc_a) {
            my $title = $doc_td->as_text;
            remove_trailing(\$title);
            my $link = $base_uri->scheme.'://'.$base_uri->host.
                $doc_a->attr('href');
            my $rmc_number;
            my $rmc = decode_utf8('RMČ');
            if ($title =~ m/^\s*(\d+)\.\s*$rmc$/ms) {
                $rmc_number = $1;
            }

            # Save.
            my $ret_ar = eval {
                $dt->execute('SELECT COUNT(*) FROM data '.
                    'WHERE Date = ? AND Title = ?',
                    $date, $title);
            };
            if ($EVAL_ERROR || ! @{$ret_ar}
                || ! exists $ret_ar->[0]->{'count(*)'}
                || ! defined $ret_ar->[0]->{'count(*)'}
                || $ret_ar->[0]->{'count(*)'} == 0) {

                print '- '.encode_utf8($title)."\n";
                my $md5 = md5($link);
                $dt->insert({
                    'Date' => $date,
                    'Title' => $title,
                    'PDF_link' => $link,
                    'RMC_number' => $rmc_number,
                    'MD5' => $md5,
                });
                # TODO Move to begin with create_table().
                $dt->create_index(['Date', 'Title'], 'data',
                    1, 1);
                $dt->create_index(['MD5'], 'data', 1, 1);
            }
        }
    }
}

# Get database date from web date.
sub get_db_date {
	my $web_date = shift;
	my ($day, $mon, $year) = $web_date
		=~ m/^\s*(\d+)\s*\.\s*(\d+)\s*.\s*(\d+)\s*$/ms;
	my $time = timelocal(0, 0, 0, $day, $mon - 1, $year - 1900);
	return strftime('%Y-%m-%d', localtime($time));
}

# Get root of HTML::TreeBuilder object.
sub get_root {
	my $uri = shift;
	my $get = $ua->get($uri->as_string);
	my $data;
	if ($get->is_success) {
		$data = $get->content;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
	my $tree = HTML::TreeBuilder->new;
	$tree->parse(decode_utf8($data));
	return $tree->elementify;
}

# Get link and compute MD5 sum.
sub md5 {
	my $link = shift;
	my (undef, $temp_file) = tempfile();
	my $get = $ua->get($link, ':content_file' => $temp_file);
	my $md5_sum;
	if ($get->is_success) {
		my $md5 = Digest::MD5->new;
		open my $temp_fh, '<', $temp_file;
		$md5->addfile($temp_fh);
		$md5_sum = $md5->hexdigest;
		close $temp_fh;
		unlink $temp_file;
	}
	return $md5_sum;
}

# Removing trailing whitespace.
sub remove_trailing {
	my $string_sr = shift;
	${$string_sr} =~ s/^\s*//ms;
	${$string_sr} =~ s/\s*$//ms;
	return;
}
