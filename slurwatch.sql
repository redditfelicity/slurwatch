-- 
-- SQL schema for slurwatch.  This is designed for PostgreSQL (it uses the
-- SERIAL type), but could be converted to another database easily enough.
--
-- 2013-06-24 <felicity@misandri.st> (/u/felicity_dont_real), released into
-- the public domain.

-- posts table: holds the list of posts we've seen, and some metadata
-- about them.
DROP TABLE IF EXISTS post CASCADE;
CREATE TABLE post (
	id		SERIAL PRIMARY KEY,
	-- Reddit's id for the post.
	name		VARCHAR(16) NOT NULL,
	-- Textual subreddit name.
	subreddit	VARCHAR(64) NOT NULL,
	-- Reference to subreddit table
	subreddit_id	INT NOT NULL REFERENCES subreddit(id)
				ON DELETE CASCADE
				ON UPDATE CASCADE,
	
	-- Absolute URL to the default comments page.
	permalink	VARCHAR(512) NOT NULL,
	score		INT NOT NULL,
	ups		INT NOT NULL,
	downs		INT NOT NULL,
	comments	INT NOT NULL,
	-- All of these are seconds since the UTC epoch.
	first_seen	INT NOT NULL,
	last_seen	INT NOT NULL,
	posted		INT NOT NULL,

	UNIQUE (name),
	UNIQUE (permalink)
);
CREATE INDEX post_name_idx ON post(name);
CREATE INDEX post_permalink_idx ON post(permalink);

-- comments table: contains matched comments, including metadata and the
-- comment body (in both markdown and HTML).  This only stores comments we've
-- actually matched, not every comment seen.
DROP TABLE IF EXISTS comment CASCADE;
CREATE TABLE comment (
	id		SERIAL PRIMARY KEY,
	-- Reddit's id for the comment.
	name		VARCHAR(16) NOT NULL,
	author		VARCHAR(64) NOT NULL,
	post		INTEGER NOT NULL REFERENCES post(id)
				ON DELETE CASCADE
				ON UPDATE CASCADE,
	-- Absolutely URL to the comment.
	permalink	VARCHAR(512) NOT NULL,
	-- Post body in both markdown (text) and HTML (text_html) form.
	-- These are stored exactly the way Reddit returns them; in particular,
	-- text_html is double-escaped.
	text		TEXT,
	text_html	TEXT,
	-- UTC seconds since the epoch.
	posted		INT NOT NULL,
	ups		INT NOT NULL,
	downs		INT NOT NULL,
	score		INT NOT NULL,

	UNIQUE(name),
	UNIQUE(permalink)
);
CREATE INDEX comment_name_idx ON comment(name);
CREATE INDEX comment_permalink_idx ON comment(permalink);

-- slurs: contains the list of words we consider when matching a comment.
DROP TABLE IF EXISTS slur CASCADE;
CREATE TABLE slur (
	id		SERIAL PRIMARY KEY,
	slur		VARCHAR(32),

	UNIQUE(slur)
);

INSERT INTO slur(slur) VALUES('fag');
INSERT INTO slur(slur) VALUES('fags');
INSERT INTO slur(slur) VALUES('faggot');
INSERT INTO slur(slur) VALUES('faggots');
INSERT INTO slur(slur) VALUES('dyke');
INSERT INTO slur(slur) VALUES('dykes');
INSERT INTO slur(slur) VALUES('bitch');
INSERT INTO slur(slur) VALUES('bitches');
INSERT INTO slur(slur) VALUES('cunt');
INSERT INTO slur(slur) VALUES('cunts');
INSERT INTO slur(slur) VALUES('whore');
INSERT INTO slur(slur) VALUES('whores');
INSERT INTO slur(slur) VALUES('mangina');
INSERT INTO slur(slur) VALUES('manginas');
INSERT INTO slur(slur) VALUES('nigger');
INSERT INTO slur(slur) VALUES('niggers');
INSERT INTO slur(slur) VALUES('paki');
INSERT INTO slur(slur) VALUES('pakis');
INSERT INTO slur(slur) VALUES('tranny');
INSERT INTO slur(slur) VALUES('trannies');
INSERT INTO slur(slur) VALUES('shemale');
INSERT INTO slur(slur) VALUES('shemales');
INSERT INTO slur(slur) VALUES('retard');
INSERT INTO slur(slur) VALUES('retarded');
INSERT INTO slur(slur) VALUES('retards');

-- subreddits: contains a list of subreddits we've seen, and those we want to
-- scan.  Only subreddits with active=1 are scanned by slurwatch, and rest are
-- those we picked up via /r/all.
DROP TABLE IF EXISTS subreddit CASCADE;
CREATE TABLE subreddit (
	id	SERIAL PRIMARY KEY,
	name	VARCHAR(64),
	active	INT NOT NULL,

	UNIQUE(name)
);

-- An index for looking up subreddit by name, ignoring case.
CREATE UNIQUE INDEX subreddit_name_lower_idx ON subreddit(LOWER(name));

INSERT INTO subreddit(name, active) VALUES('atheism');
INSERT INTO subreddit(name, active) VALUES('AdviceAnimals', 1);
INSERT INTO subreddit(name, active) VALUES('announcements', 1);
INSERT INTO subreddit(name, active) VALUES('AskReddit', 1);
INSERT INTO subreddit(name, active) VALUES('aww', 1);
INSERT INTO subreddit(name, active) VALUES('bestof', 1);
INSERT INTO subreddit(name, active) VALUES('blog', 1);
INSERT INTO subreddit(name, active) VALUES('funny', 1);
INSERT INTO subreddit(name, active) VALUES('IAmA', 1);
INSERT INTO subreddit(name, active) VALUES('movies', 1);
INSERT INTO subreddit(name, active) VALUES('Music', 1);
INSERT INTO subreddit(name, active) VALUES('pics', 1);
INSERT INTO subreddit(name, active) VALUES('politics', 1);
INSERT INTO subreddit(name, active) VALUES('science', 1);
INSERT INTO subreddit(name, active) VALUES('technology', 1);
INSERT INTO subreddit(name, active) VALUES('todayilearned', 1);
INSERT INTO subreddit(name, active) VALUES('videos', 1);
INSERT INTO subreddit(name, active) VALUES('worldnews', 1);
INSERT INTO subreddit(name, active) VALUES('WTF', 1);
INSERT INTO subreddit(name, active) VALUES('mensrights', 1);
INSERT INTO subreddit(name, active) VALUES('unitedkingdom', 1);
INSERT INTO subreddit(name, active) VALUES('ukpolitics', 1);
INSERT INTO subreddit(name, active) VALUES('gaming', 1);
INSERT INTO subreddit(name, active) VALUES('gifs', 1);
