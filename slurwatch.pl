#! /usr/bin/env perl
#
# slurwatch scanner: loads comments on Reddit and scans them for slurs (or
# or other words), storing the results in a database.  Use it with 
# slurwatch.fcgi, the web-based front end viewer.
#
# 2013-06-24 <felicity@misandri.st> (/u/felicity_dont_real), released into
# the public domain.

use warnings;
use strict;

use LWP::UserAgent;
use JSON qw/decode_json/;
use DBI;
use HTML::Strip;
use Getopt::Std;
use Try::Tiny;
use Cwd qw/abs_path/;
use File::Basename qw/dirname/;
use Data::Dumper;

# Get the directory name we're running from
my $scriptname = abs_path($0);
my $dirname = dirname($scriptname);

my %config = do "$dirname/config";

# Which subreddits to scan.  Note that 'all' is listed here to pick up the
# occasional popular post in other subs.
my @subreddits = qw/atheism AdviceAnimals announcements AskReddit aww bestof
	blog funny IAmA movies Music pics politics science technology
	todayilearned videos worldnews WTF mensrights unitedkingdom
	ukpolitics gaming gifs all/;

# Parameters for re-scanning posts which have already been seen.  If a post
# was last seen over $maxage seconds ago, it will always be re-scanned (as
# long as it's still in top.json).  Otherwise, it will be re-scanned if was
# last seen more than $minage seconds ago, *and* the number of comments is
# at least ($minnew * 100)% of the previous number of comments.  (For example,
# if $minnew is 1.5, there were previously 50 comments, and now there are 75 
# comments, it will be re-scanned.)
#
# The purpose of this is to avoid having to re-load every post on each run,
# unless it's likely that there are new comments.
my $minage = 3600;
my $maxage = 7200;
my $minnew = 1.5;

# Comments less than $minscore will not be indexed.  Change this to 10 for
# SRS rules.
my $minscore = 1;

my $hs = HTML::Strip->new;

# Create the LWP user-agent and set a custom User-Agent header.  This is
# required for the Reddit API.
my $ua = new LWP::UserAgent;
$ua->agent("reddit slurwatch by /u/felicity_dont_real");

# Parse command-line options.
our ($opt_v);	# -v: show verbose output while running.
getopts('v');

# Connect to the database.  Turn autocommit off explicitly, as some drivers
# enable it by default.
my $dbh = DBI->connect("dbi:Pg:" . $config{dbconn}, $config{dbuser}, $config{dbpass},
			{ AutoCommit => 0})
	or die;

# For performance, prepare all the queries we need in advance.

my $sth_post_byname = $dbh->prepare("SELECT * FROM post WHERE name = ?") or die;
my $sth_post_update = $dbh->prepare("UPDATE post SET last_seen = ?, comments = ?, "
				   ."ups = ?, downs = ?, score = ? WHERE name = ?") or die;
my $sth_post_insert = $dbh->prepare("INSERT INTO post (name, subreddit, permalink, score, "
				   ."ups, downs, comments, first_seen, last_seen, posted) "
				   ."VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
				   ."RETURNING id") or die;

my $sth_comment_byname = $dbh->prepare("SELECT * FROM comment WHERE name = ?") or die;
my $sth_comment_insert = $dbh->prepare("INSERT INTO comment (name, post, permalink, "
				      ."text, posted, ups, downs, score, text_html, "
				      ."author) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
				      ."RETURNING id") or die;
my $sth_comment_update = $dbh->prepare("UPDATE comment SET text = ?, ups = ?, downs = ?, "
				      ."score = ?, text_html = ? WHERE id = ?") or die;

# Load slurs from the database.  We keep the database id of each slur, but
# currently don't use it for anything.  In future, it might be nice to track
# which slur is used by which comment.
my $s = $dbh->prepare("SELECT id, slur FROM slur");
$s->execute;
my %slurs;
while (my @row = $s->fetchrow_array) {
	$slurs{$row[1]} = $row[0];
}

# The regex used to match comments.  \b matches a word boundary (space,
# punctuation, etc).
my $regex = "\\b(" . join("|", keys %slurs) . ")\\b";

# Check if a comment contains a slur.  This expects to be passed the HTML
# rendered version of the body.
sub check_slur {
	my $text = shift;

	# Strip HTML tags.
	my $strip = $hs->parse($text);
	$hs->eof;

	# Remove quotes (lines starting with '>').
	$text =~ s/^>.*$//gm;

	if ($text =~ /$regex/) {
		return 1;
	} else {
		return 0;
	}
}

# Process one comment and all its children (replies).  This calls itself
# recursively to handle children.

my $ind = 2; # state for comment printing in verbose mode
sub do_a_comment {
	my $sr = shift;
	my $post = shift;
	my $postid = shift;
	my $comment = shift;

	# $name is the id of the comment, e.g. 'caosqk9'; combined with the
	# post URL, this gives us a permalink to the comment.
	my $name = $comment->{id};
	my $permalink = "http://www.reddit.com" . $post->{permalink} . "$name";

	my $created = $comment->{created_utc};
	my $author = $comment->{author};

	# Unlike posts, comments don't seem to have a 'score' attribute.
	# However, ($ups - $downs) is guaranteed to be correct even with
	# vote fuzzing.
	my $ups = $comment->{ups};
	my $downs = $comment->{downs};
	my $score = $ups - $downs;

	my $body = $comment->{body};
	my $body_html = $comment->{body_html};

	# Produce an indented version of the body, only used for printing
	# the comment text to stdout in verbose mode.
	my $x = $body;
	my $i = " " x $ind;
	$x =~ s/^/$i/sm;

	if (check_slur($body_html) and $score >= $minscore) {
		if ($opt_v) {
			print "$i/u/$author $score points ($ups|$downs)\n";
			print "$x\n\n";
		}

		# See if this comment is already in the database.
		my $cmtid = undef;
		my $rc = $sth_comment_byname->execute($name);

		if (my $row = $sth_comment_byname->fetchrow_hashref) {
			# It already exists, so update score and text
			$cmtid = $row->{id};
			$rc = $sth_comment_update->execute($body, $ups, $downs, $score,
					$body_html, $cmtid);
		} else {
			# Insert a new comment
			$rc = $sth_comment_insert->execute($name, $postid, $permalink,
					$body, $created, $ups, $downs, $score, $body_html,
					$author);
			my @row = $sth_comment_insert->fetchrow_array;
			$cmtid = $row[0];
		}
		$dbh->commit;
	}

	#print Dumper $comment;

	# Process this comment's children recursively.  If there are no replies,
	# the 'replies' attribute will be "", an empty string.  If the comment
	# thread becomes to deep, the next comment is replaced with an object of
	# type "more".  We skip anything that's not of type "t1" (a comment) to
	# avoid these.

	$ind += 2;
	if (defined($comment->{replies}) and $comment->{replies} ne "") {
		foreach my $reply (@{$comment->{replies}->{data}->{children}}) {
			next if $reply->{kind} ne "t1";
			do_a_comment($sr, $post, $postid, $reply->{data});
		}
	}
	$ind -= 2;
}

# Statistics.
my $nposts = 0;	# Number of posts seen
my $ndone = 0;	# Number actually scanned.

# Handle one post.  This function will determine whether the post should be
# re-scanned (if we've seen it before), and if not, it will be skipped.
sub do_a_post {
	my $sr = shift;		# Subreddit name (text)
	my $post = shift;	# Decoded post object (from JSON)

	# $name is the id of the post, e.g. '1gxjyt'.  From this we create
	# the permalink URL, and the JSON URL to load comments.
	my $name = $post->{id};
	my $commentsurl = "http://www.reddit.com/r/$sr/comments/$name.json?limit=500&depth=40";
	my $permalink = "http://www.reddit.com" . $post->{permalink};

	my $ups = $post->{ups};
	my $downs = $post->{downs};
	my $score = $post->{score};
	my $comments = $post->{num_comments};
	my $created = $post->{created_utc};

	# See if this post is already in the database, meaning we've seen it
	# before.
	my $postid = undef;
	my $lastseen = undef;
	my $age = undef;

	my $rc = $sth_post_byname->execute($name);

	if (my $row = $sth_post_byname->fetchrow_hashref) {
		# It already exists, so extract the last seen time and previous
		# comment count
		$postid = $row->{id};
		$lastseen = $row->{last_seen};
		my $old_comments = $row->{comments};
	
		# Decide whether to re-scan the post or skip it.  The logic for
		# doing this is explained further up.

		$age = time - $lastseen;

		my $newcomms;
		# Work out the old:new comment ratio.  If the post previously
		# had no comments, but now has some ($old_comments == 0,
		# $comments > 0), force the ratio to 2.  Technically this should
		# be infinity, but...
	
		if ($old_comments > 0) {
			$newcomms = $comments / $old_comments;
		} elsif ($comments == 0) {
			$newcomms = 0;
		} else {
			$newcomms = 2;
		}

		# Determine whether to actually re-scan.
		my $doit = 0;
		$doit = 1 if ($age >= $maxage);
		$doit = 1 if ($age >= $minage and $newcomms >= $minnew);

		print "[age: $age; comment ratio: $newcomms ($old_comments -> "
		     ."$comments)] $permalink" if $opt_v;
		
		# We don't want to see this topic; roll back any database changes
		# (of which there should be none anyway) and return.
		if ($doit == 0) {
			$dbh->rollback;
			print "  ... skip\n" if $opt_v;
			return;
		}

		# Fall through to rescan.
		print " ... update\n" if $opt_v;
		my $rc = $sth_post_update->execute(time, $comments, $ups, $downs, $score, $name);
	} else {
		# Insert a new post
		my $rc = $sth_post_insert->execute($name, $sr, $permalink, $score,
					$ups, $downs, $comments, time, time, $created);
		my @row = $sth_post_insert->fetchrow_array;

		$postid = $row[0];
		$lastseen = time;
		$age = 0;
		print "[new] $permalink\n" if $opt_v;
	}
	$dbh->commit;

	# Fetch the comments JSON.  On failure, abort any pending database updates
	# and return: the post should be re-tried later.
	my $r = $ua->get($commentsurl) or die "$commentsurl: $!";
	if (!$r->is_success) {
		print "  HTTP error: " . $r->status_line . "\n" if $opt_v;
		return;
	}
	my $json = $r->decoded_content;

	$ndone++;

	my $resp;
	try {
		$resp = decode_json($json);
	} catch {
		print "  JSON decoding error\n" if $opt_v;
		return;
	};

	#print Dumper $resp;

	#foreach my $comment (@{$resp->[1]->{data}->{children}}) {
	foreach my $comment (@{$resp}) {
		foreach my $c (@{$comment->{data}->{children}}) {
			#print Dumper $c;
			next unless $c->{kind} eq "t1";
			do_a_comment($sr, $post, $postid, $c->{data});
		}
	}
}

# Handle one subreddit.  Loads the top posts (top.json) for the sub and
# passes each post to do_a_post.
sub do_a_sub {
	my $sr = shift;
	my $topurl = "http://www.reddit.com/r/$sr/top.json?limit=100";

	my $r = $ua->get($topurl);

	# If we encounter an error loading the sub, just return.  We
	# will try again on the next run.
	if (!$r->is_success) {
		print "HTTP error: " . $r->status_line . " [$topurl]\n"
			if $opt_v;
		return;
	}

	my $json = $r->decoded_content;
	my $resp;
	try {
		$resp = decode_json($json);
	} catch {
		print "JSON decoding error [$topurl]\n" if $opt_v;
		return;
	};

	foreach my $post (@{$resp->{data}->{children}}) {
		my $sr = $post->{data}->{subreddit};
		do_a_post($sr, $post->{data});
		$nposts++;
	}
}

my $then = time;

# It would be more efficient to load posts from all subs at once, like this:
#my $subs = join("+", @subreddits);
#do_a_sub($subs);
# However, that requires implementing paging to retrieve more than 100 results,
# so for now do it this way instead:

foreach my $sr (@subreddits) {
	do_a_sub($sr);
}

my $now = time;

print "Runtime: " . ($now - $then) . " sec, $nposts posts, did $ndone\n" if $opt_v;
