﻿/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// Formatting posts.
module dfeed.web.web.view.post;

import std.algorithm.iteration : map;
import std.array : array, join, replicate;
import std.conv : text;
import std.exception : enforce;

import ae.net.ietf.message : Rfc850Message;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query;
import dfeed.message : Rfc850Post, idToUrl, idToFragment;
import dfeed.web.web : PostInfo, getPost, idToThreadUrl, formatShortTime, html, summarizeTime, formatBody, formatLongTime, getPostInfo;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.post : getParentLink, miniPostInfo, getPostActions, postActions, postLink;
import dfeed.web.web.request : user;

string[] formatPostParts(Rfc850Post post)
{
	string[] partList;
	void visitParts(Rfc850Message[] parts, int[] path)
	{
		foreach (int i, part; parts)
		{
			if (part.parts.length)
				visitParts(part.parts, path~i);
			else
			if (part.content !is post.content)
			{
				string partUrl = ([idToUrl(post.id, "raw")] ~ array(map!text(path~i))).join("/");
				with (part)
					partList ~=
						(name || fileName) ?
							`<a href="` ~ encodeHtmlEntities(partUrl) ~ `" title="` ~ encodeHtmlEntities(mimeType) ~ `">` ~
							encodeHtmlEntities(name) ~
							(name && fileName ? " - " : "") ~
							encodeHtmlEntities(fileName) ~
							`</a>` ~
							(description ? ` (` ~ encodeHtmlEntities(description) ~ `)` : "")
						:
							`<a href="` ~ encodeHtmlEntities(partUrl) ~ `">` ~
							encodeHtmlEntities(mimeType) ~
							`</a> part` ~
							(description ? ` (` ~ encodeHtmlEntities(description) ~ `)` : "");
			}
		}
	}
	visitParts(post.parts, null);
	return partList;
}

// ***********************************************************************

void discussionVSplitPost(string id)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	formatPost(post, null);
}

// ***********************************************************************

void formatPost(Rfc850Post post, Rfc850Post[string] knownPosts, bool markAsRead = true)
{
	string gravatarHash = getGravatarHash(post.authorEmail);

	string[] infoBits;

	auto parentLink = getParentLink(post, knownPosts);
	if (parentLink)
		infoBits ~= `Posted in reply to ` ~ parentLink;

	auto partList = formatPostParts(post);
	if (partList.length)
		infoBits ~=
			`Attachments:<ul class="post-info-parts"><li>` ~ partList.join(`</li><li>`) ~ `</li></ul>`;

	if (knownPosts is null && post.cachedThreadID)
		infoBits ~=
			`<a href="` ~ encodeHtmlEntities(idToThreadUrl(post.id, post.cachedThreadID)) ~ `">View in thread</a>`;

	string repliesTitle = `Replies to `~encodeHtmlEntities(post.author)~`'s post from `~encodeHtmlEntities(formatShortTime(post.time, false));

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` ~ // Fixed layout dummies
			`<tr class="post-header"><th colspan="2">` ~
				`<div class="post-time">`, summarizeTime(time), `</div>` ~
				`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="permalink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr class="mini-post-info-cell">` ~
				`<td colspan="2">`
		); miniPostInfo(post, knownPosts); html.put(
				`</td>` ~
			`</tr>` ~
			`<tr>` ~
				`<td class="post-info">` ~
					`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 80);
		if (infoBits.length)
		{
			html.put(`<hr>`);
			foreach (b; infoBits)
				html.put(`<div class="post-info-bit">`, b, `</div>`);
		}
		else
			html.put(`<br>`);
		auto actions = getPostActions(post.msg);
		foreach (n; 0..actions.length)
			html.put(`<br>`); // guarantee space for the "toolbar"

		html.put(
					`<div class="post-actions">`), postActions(actions), html.put(`</div>` ~
				`</td>` ~
				`<td class="post-body">` ~
//		); miniPostInfo(post, knownPosts); html.put(
					`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td>` ~
			`</tr>` ~
			`</table>` ~
			`</div>`);

		if (post.children)
		{
			html.put(
				`<table class="post-nester"><tr>` ~
				`<td class="post-nester-bar" title="`, /* for IE */ repliesTitle, `">` ~
					`<a href="#`), html.putEncodedEntities(idToFragment(id)), html.put(`" ` ~
						`title="`, repliesTitle, `"></a>` ~
				`</td>` ~
				`<td>`);
			foreach (child; post.children)
				formatPost(child, knownPosts);
			html.put(`</td>` ~
				`</tr></table>`);
		}
	}

	if (post.rowid && markAsRead)
		user.setRead(post.rowid, true);
}

struct InfoRow { string name, value; }

/// Alternative post formatting, with the meta-data header on top
void formatSplitPost(Rfc850Post post, bool footerNav)
{
	scope(success) user.setRead(post.rowid, true);

	InfoRow[] infoRows;
	string parentLink;

	infoRows ~= InfoRow("From", encodeHtmlEntities(post.author));
	//infoRows ~= InfoRow("Date", format("%s (%s)", formatLongTime(post.time), formatShortTime(post.time, false)));
	infoRows ~= InfoRow("Date", formatLongTime(post.time));

	if (post.parentID)
	{
		auto parent = post.parentID ? getPostInfo(post.parentID) : null;
		if (parent)
		{
			parentLink = postLink(parent.rowid, parent.id, parent.author);
			infoRows ~= InfoRow("In reply to", parentLink);
		}
	}

	string[] replies;
	foreach (int rowid, string id, string author; query!"SELECT `ROWID`, `ID`, `Author` FROM `Posts` WHERE ParentID = ?".iterate(post.id))
		replies ~= postLink(rowid, id, author);
	if (replies.length)
		infoRows ~= InfoRow("Replies", `<span class="avoid-wrap">` ~ replies.join(`,</span> <span class="avoid-wrap">`) ~ `</span>`);

	auto partList = formatPostParts(post);
	if (partList.length)
		infoRows ~= InfoRow("Attachments", partList.join(", "));

	string gravatarHash = getGravatarHash(post.authorEmail);

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="split-post forum-table" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="post-header"><th>` ~
				`<div class="post-time">`, summarizeTime(time), `</div>` ~
				`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="`, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr><td class="horizontal-post-info">` ~
				`<table><tr>` ~
					`<td class="post-info-avatar" rowspan="`, text(infoRows.length), `">`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 48);
		html.put(
					`</td>` ~
					`<td><table>`);
		foreach (a; infoRows)
			html.put(`<tr><td class="horizontal-post-info-name">`, a.name, `</td><td class="horizontal-post-info-value">`, a.value, `</td></tr>`);
		html.put(
					`</table></td>` ~
					`<td class="post-info-actions">`), postActions(getPostActions(post.msg)), html.put(`</td>` ~
				`</tr></table>` ~
			`</td></tr>` ~
			`<tr><td class="post-body">` ~
				`<table class="post-layout"><tr class="post-layout-header"><td>`);
		miniPostInfo(post, null);
		html.put(
				`</td></tr>` ~
				`<tr class="post-layout-body"><td>` ~
					`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td></tr>` ~
				`<tr class="post-layout-footer"><td>`
					); postFooter(footerNav, infoRows[1..$]); html.put(
				`</td></tr></table>` ~
			`</td></tr>` ~
			`</table>` ~
			`</div>`
		);
	}
}

void postFooter(bool footerNav, InfoRow[] infoRows)
{
	html.put(
		`<table class="post-footer"><tr>`,
			(footerNav ? `<td class="post-footer-nav"><a href="javascript:navPrev()">&laquo; Prev</a></td>` : null),
			`<td class="post-footer-info">`);
	foreach (a; infoRows)
		html.put(`<div><span class="horizontal-post-info-name">`, a.name, `</span>: <span class="horizontal-post-info-value">`, a.value, `</span></div>`);
	html.put(
			`</td>`,
			(footerNav ? `<td class="post-footer-nav"><a href="javascript:navNext()">Next &raquo;</a></td>` : null),
		`</tr></table>`
	);
}

void discussionSplitPost(string id)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	formatSplitPost(post, true);
}