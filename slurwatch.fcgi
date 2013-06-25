#! /usr/pkg/bin/perl
#
# Web front-end for slurwatch.  It reads the list of comments stored in
# the database and presents them in a nice web page.
#
# This can run as either a CGI script or a FastGI script, but for performance,
# FastCGI is much preferred, for example (with mod_fcgid):
#
#   <Directory "/var/www/misandri.st/fcgi-bin">
#       Options         ExecCGI
#       AllowOverride   All
#       Require         all granted
#       AddHandler      fcgid-script .fcgi
#   </Directory>
#
#   Alias /r/slurwatch /var/www/misandri.st/slurwatch/slurwatch.fcgi
#
# Note that it expects slurwatch.css to be in the document root.  This should
# probably be fixed.
#
# 2013-06-24 <felicity@misandri.st> (/u/felicity_dont_real), released
# into the public domain.

use warnings;
use strict;

use DBI;
use CGI::Fast;
use CGI qw/escapeHTML/;
use HTML::Entities;
use HTML::Strip;
use Cwd qw/abs_path/;
use File::Basename qw/dirname/;

# Get the directory name we're running from and load the configuration.
my $scriptname = abs_path($0);
my $dirname = dirname($scriptname);

my %config = do "$dirname/config";

my $hs = HTML::Strip->new;
my $limit = 200;

# General function to display an error response.
sub error {
	my $errtext = shift;
	print "Status: 500 Internal server error\n";
	print "Content-Type: text/plain;charset=UTF-8\n";
	print "\n";
	print "Error: $errtext\n"
}

# Convert a time span in seconds to a textual representation, e.g.
# "2 hours ago".
sub ago {
	my $secs = shift;
	return int($secs / (60 * 60 * 24)) . " days ago" if $secs > (60 * 60 * 24);
	return int($secs / (60 * 60)) . " hours ago" if $secs > (60 * 60);
	return int($secs / 60) . " minutes ago" if $secs > 60;
	return "$secs seconds ago";
}

# Main request loop.
while (my $cgi = new CGI::Fast) {
	# Connect to the database.
	my $dbh;
	if (!($dbh = DBI->connect("dbi:Pg:" . $config{dbconn},
				$config{dbuser}, $config{dbpass}))) {
		error "cannot connect to the database";
		next;
	}

	# Load list of slurs from the database, so we can highlight them in
	# the output.
	my @slurs;
	my $sth = $dbh->prepare("SELECT slur FROM slur");
	$sth->execute;
	while (my @slur = $sth->fetchrow_array) {
		push @slurs, $slur[0];
	}
	my $regex = "(\\b)(" . join("|", @slurs) . ")(\\b)";

	# Header.  Note that we concatenate output to $output and print it all
	# at once, rather than printing as we go along.
	my $output = <<EOF;
<!DOCTYPE html>
<html>
	<head>
		<title>Reddit slurwatch</title>
		<link rel="stylesheet" href="/slurwatch.css">
	</head>
	<body>
		<h1>Reddit slurwatch</h1>

		<p class='intro'>Welcome to Reddit slurwatch.  It displays Reddit comments,
		from the default subs and a few others, which contain slurs.
		Question?  Comments?  <a href="http://www.reddit.com/u/felicity_dont_real"
		>/u/felicity_dont_real</a> would love to hear them.</p>

		<p>NB: Most ableist slurs are excluded simply because they would completely overwhelm
		anything else.  Otherwise, send me a PM if you have suggestions for more words
		to add.</p>

		<p>NB #2: The fact that a comment is listed here isn't a value judgement on the
		comment.  slurwatch simply lists any comment that contains one of the words in
		its list; it's not an AI and can't determine the context the word is being
		used in.</p>

		<p>NB #3: Here is the current list of subreddits: <tt>atheism AdviceAnimals
		announcements AskReddit aww bestof blog funny IAmA movies Music pics politics
		science technology todayilearned videos worldnews WTF mensrights unitedkingdom
		ukpolitics gaming gifs</tt>.  It also scans /r/all, so it will sometimes pick
		up popular posts outside this list.</p>

		<p>NB #4: slurwatch will now only display comments with a score of 2 or
		higher (instead of 1 or higher).  This is to filter out comments in subs
		which hide comment scores; these comments appear to have a score of 1, but
		might actually be scored much lower.</p>
EOF

	# Fetch a list of comments from the database.  For now this just displays the
	# most recently posted 200 comments, but it would be nice to support paging.
	$sth = $dbh->prepare("SELECT comment.name AS comment_name, author, "
			    ."comment.permalink AS comment_permalink, text_html, "
			    ."comment.posted AS posted, "
			    ."comment.ups AS ups, comment.downs AS downs, comment.score AS score, "
			    ."subreddit FROM comment, post "
			    ."WHERE comment.post = post.id AND comment.score > 1 "
			    ."ORDER BY comment.posted DESC LIMIT $limit");

	my $rc = $sth->execute;

	# Print each actual comment.  divs, not tables.
	while (my $row = $sth->fetchrow_hashref) {
		my $authorurl = "http://www.reddit.com/u/" . escapeHTML($row->{author});
		my $author = escapeHTML($row->{author});
		my $score = escapeHTML($row->{score});
		my $ups = escapeHTML($row->{ups});
		my $downs = escapeHTML($row->{downs});
		my $permalink = escapeHTML($row->{comment_permalink});
		my $text = $hs->parse(decode_entities($row->{text_html}));
		$text =~ s{$regex}{$1<strong>$2</strong>$3}g;
		my $time = escapeHTML(ago(time - $row->{posted}));
		my $sr = escapeHTML($row->{subreddit});
		my $srurl = "http://www.reddit.com/r/" . $sr;
		$output .= <<EOF;
<div class="comment">
	<div class="comment-header"><a href="$authorurl" class="author">/u/$author</a>
	$score points $time (<span class="ups">$ups</span>|<span class="downs">$downs</span>)
	in <a href="$srurl" class="sr">/r/$sr</a> (<a href="$permalink">link</a>)</div>
	<div class="comment-text">$text</div>
</div>
EOF
	}

	$dbh->disconnect;

	$output .= "</body></html>";

	print "Status: 200 OK\n";
	print "Content-Type: text/html;charset=UTF-8\n";
	print "\n";
	print $output;
}
