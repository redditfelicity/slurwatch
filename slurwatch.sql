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
