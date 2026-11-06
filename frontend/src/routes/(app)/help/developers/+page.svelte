<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';

  // Developer documentation — explains what bots and the API can do
  // and how to use them. Lives at /help/developers and is the only
  // human-readable reference outside `docs/SPEC.md` (which targets
  // contributors, not users). Sidebar-on-the-left layout with anchor
  // links so users can scroll the whole thing or jump to a section.

  type Section = { id: string; label: string };

  const sections: Section[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'choosing', label: 'Personal app vs bot' },
    { id: 'authentication', label: 'Authentication' },
    { id: 'bots', label: 'Bots in depth' },
    { id: 'webhooks', label: 'Webhooks' },
    { id: 'endpoints', label: 'API endpoints' },
    { id: 'limits', label: 'Rate limits & scopes' },
    { id: 'examples', label: 'Examples' },
  ];

  let active = $state<string>('overview');

  // IntersectionObserver tracks which section is currently in view so
  // the sidebar highlight stays in sync with the scroll position.
  let observer: IntersectionObserver | null = null;

  function setupObserver() {
    if (typeof window === 'undefined') return;
    observer?.disconnect();
    observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            active = e.target.id;
          }
        }
      },
      // Trigger when the section's top crosses ~30% from the viewport
      // top — close enough to "this is what the reader is looking at"
      // for a docs page that's read top-to-bottom.
      { rootMargin: '-30% 0px -60% 0px', threshold: 0 },
    );
    for (const s of sections) {
      const el = document.getElementById(s.id);
      if (el) observer.observe(el);
    }
  }

  $effect(() => {
    setupObserver();
    return () => observer?.disconnect();
  });

  function jumpTo(id: string) {
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
</script>

<svelte:head>
  <title>Developer documentation — {$instanceName}</title>
</svelte:head>

<div class="docs-shell">
  <aside class="docs-sidebar" aria-label="Documentation sections">
    <h2 class="sidebar-heading">Developer docs</h2>
    <nav class="sidebar-nav">
      {#each sections as s (s.id)}
        <button
          type="button"
          class="sidebar-item"
          class:sidebar-item-active={active === s.id}
          onclick={() => jumpTo(s.id)}
        >
          {s.label}
        </button>
      {/each}
    </nav>
    <a class="sidebar-cta" href="/settings/developers">Open Developer Tools →</a>
  </aside>

  <article class="docs-content">
    <section id="overview" class="docs-section">
      <h1>Developer documentation</h1>
      <p class="lead">
        {$instanceName} exposes a Mastodon-compatible REST API. You can build clients,
        automations, dashboards, scrapers (please don't), or bots that interact with
        the platform on your behalf or under their own identity.
      </p>
      <p>
        Everything you can do in the UI you can also do over the API: post, follow,
        DM, react, manage groups and pages, run searches, and stream timelines in
        real time. The same endpoints power our own web app, so they're tested
        every time you reload the page.
      </p>
      <p>
        Start by opening <a href="/settings/developers">Developer Tools</a> in your
        settings — that's where you create credentials and run quick test calls.
      </p>
    </section>

    <section id="choosing" class="docs-section">
      <h2>Personal app vs bot</h2>
      <p>
        There are two ways to talk to the API. Pick the one that fits what you're
        building.
      </p>

      <div class="choice-grid">
        <div class="choice-card">
          <h3>Personal app</h3>
          <p>
            Acts as <strong>your account</strong>. Posts show up under your handle.
            Useful for a personal client, a side-script that posts on your behalf, or
            integrating {$instanceName} into something you control.
          </p>
          <ul class="choice-pros">
            <li>Set up in seconds — one button on the Developer Tools page.</li>
            <li>Inherits your account's followers and permissions.</li>
            <li>You get notifications for activity it generates.</li>
          </ul>
        </div>

        <div class="choice-card">
          <h3>Bot</h3>
          <p>
            A separate identity with its own <code>@handle</code>, but owned by you.
            Other users can follow it independently from your main account. Marked
            with the <code>is_bot</code> flag so clients can label its posts as
            automation.
          </p>
          <ul class="choice-pros">
            <li>Own avatar, header, bio, follower graph.</li>
            <li>Per-bot rate limits and webhook settings.</li>
            <li>Disable / re-enable without touching your main account.</li>
            <li>Default cap of 4 bots per user (admin-configurable).</li>
          </ul>
        </div>
      </div>
    </section>

    <section id="authentication" class="docs-section">
      <h2>Authentication</h2>
      <p>
        Every authenticated API call carries a bearer token in the
        <code>Authorization</code> header:
      </p>
      <pre class="code-block">Authorization: Bearer YOUR_ACCESS_TOKEN</pre>
      <p>
        You can get a token two ways. Most projects only need the first one.
      </p>

      <h3>1. Direct token (recommended for personal scripts and bots)</h3>
      <p>
        When you create a personal app or bot from Developer Tools, the response
        includes a long-lived access token (default 1 year). Copy it — the secret
        and token are shown <strong>once</strong> and never again.
      </p>
      <pre class="code-block">curl -X POST https://YOUR_INSTANCE/api/v1/apps/with_token \
  -H "Authorization: Bearer YOUR_LOGIN_TOKEN" \
  -d "name=My Script"
# → {'{'} "client_id": "...", "client_secret": "...", "access_token": "..." {'}'}</pre>

      <h3>2. OAuth 2.0 authorization code</h3>
      <p>
        Use this for clients that authenticate <em>other</em> users, like a
        third-party app. PKCE is supported and preferred, but optional: a client
        that sends no <code>code_challenge</code> must present its
        <code>client_secret</code> when it exchanges the code. One of the two is
        always required.
      </p>
      <ol class="numbered-list">
        <li>
          Register the app: <code>POST /api/v1/apps</code> with
          <code>client_name</code>, <code>redirect_uris</code> and
          <code>scopes</code>. No authentication needed. Save the
          <code>client_id</code> and <code>client_secret</code>.
        </li>
        <li>
          Open <code>/oauth/authorize?client_id=…&amp;response_type=code&amp;redirect_uri=…&amp;scope=read+write</code>
          in a browser. The user signs in and approves, and you receive a
          10-minute authorization code at your <code>redirect_uri</code>. Use
          <code>urn:ietf:wg:oauth:2.0:oob</code> to have the code displayed for
          copy-paste instead.
        </li>
        <li>
          Exchange the code: <code>POST /oauth/token</code> with
          <code>grant_type=authorization_code</code>, the <code>code</code>,
          <code>client_id</code>, <code>redirect_uri</code>, and either
          <code>code_verifier</code> (PKCE) or <code>client_secret</code>.
          Credentials may also be sent as HTTP Basic.
        </li>
        <li>
          The response contains an <code>access_token</code> you can use just like
          a direct token, plus a <code>refresh_token</code> you can rotate through
          <code>grant_type=refresh_token</code>.
        </li>
        <li>
          Tokens are limited to the scopes the user approved: a
          <code>read</code> token cannot post, and no third-party token reaches
          the admin API without an <code>admin:*</code> scope.
        </li>
        <li>
          Revoke any token (yours or the user's) with
          <code>POST /oauth/revoke?token=…</code>. The endpoint is public and
          always returns 200 per RFC 7009.
        </li>
      </ol>

      <h3>Mastodon client compatibility</h3>
      <p>
        A token obtained through the OAuth flow above is served the
        Mastodon REST shapes: <code>username</code>/<code>acct</code>/<code>note</code>
        on accounts, <code>replies_count</code>/<code>reblogs_count</code>/<code>favourites_count</code>
        on statuses, boosts wrapped in <code>reblog</code>, and the
        <code>/favourite</code>, <code>/reblog</code> and
        <code>/accounts/verify_credentials</code> endpoints. Personal tokens
        from Developer Tools keep the native shape. Send
        <code>X-API-Compat: mastodon</code> or <code>native</code> to choose
        explicitly.
      </p>

      <h3>Listing and revoking your own apps</h3>
      <ul>
        <li><code>GET /api/v1/apps</code> — list your apps (returns the client_id, never the secret).</li>
        <li><code>DELETE /api/v1/apps/:id</code> — revoke the app and every token issued through it.</li>
      </ul>
    </section>

    <section id="bots" class="docs-section">
      <h2>Bots in depth</h2>

      <h3>Creating a bot</h3>
      <p>
        From <a href="/settings/developers">Developer Tools</a> click <strong>Create
        new</strong> → <strong>Bot</strong>, give it a name, and you're done. The
        backend will:
      </p>
      <ul>
        <li>Provision a new identity as a child of yours (<code>type: "bot"</code>, <code>is_bot: true</code>).</li>
        <li>Auto-generate a handle by appending a short random suffix to the name you chose.</li>
        <li>Issue an OAuth app and a 1-year access token with the <code>read write follow push</code> scope set.</li>
      </ul>
      <p>
        You'll see the credentials once. Save them in a password manager.
      </p>

      <h3>What a bot can do</h3>
      <p>
        Everything a regular account can: post, reply, boost, react, follow, DM,
        upload media, edit its own profile, subscribe to push events, run searches.
        The <code>is_bot</code> flag is a label — it doesn't restrict capability.
        Clients render bot posts with a small badge so readers can tell.
      </p>

      <h3>Bot settings</h3>
      <ul>
        <li>
          <strong>Description &amp; source code URL</strong> — published on the bot's
          profile so users know who runs it.
        </li>
        <li>
          <strong>Auto-approve follows</strong> — accept follow requests automatically.
          Useful for public bots; off by default.
        </li>
        <li>
          <strong>Posts per hour</strong> — per-bot rate limit (1–1000). Leave blank
          to use the instance default.
        </li>
        <li>
          <strong>Active flag</strong> — pause a bot without deleting it. While
          inactive the token still authenticates but the bot can't post.
        </li>
      </ul>

      <h3>Managing credentials</h3>
      <ul>
        <li><code>GET /api/v1/bots</code> — list your bots and their apps.</li>
        <li><code>POST /api/v1/bots</code> — create one (also issues credentials).</li>
        <li><code>POST /api/v1/bots/:id/regenerate</code> — burn old credentials and issue new ones in one call. Use after a token leak.</li>
        <li><code>DELETE /api/v1/bots/:id</code> — soft-delete the bot and revoke all its tokens. Restore is admin-only.</li>
      </ul>
    </section>

    <section id="webhooks" class="docs-section">
      <h2>Webhooks</h2>
      <p>
        Bots can subscribe to events with an outbound webhook. We POST a JSON
        body to a URL you choose, sign it with HMAC-SHA256, and retry a few times
        if your endpoint is down. Webhooks are the right move when your bot
        responds to mentions, replies, or DMs without you having to poll the API.
      </p>

      <h3>Setting one up</h3>
      <ol class="numbered-list">
        <li>
          Open <a href="/settings/developers">Developer Tools</a>, find your bot,
          and click the <strong>Webhook</strong> panel.
        </li>
        <li>
          Paste your URL and save. We show you the signing secret <strong>once</strong>
          — save it now, you won't see it again.
        </li>
        <li>
          When you change the URL or want to rotate the secret, save again and
          you'll get a fresh secret. Old signatures will stop verifying.
        </li>
        <li>
          <code>Remove</code> clears the URL and cancels any in-flight deliveries.
        </li>
      </ol>

      <h3>What events fire</h3>
      <p>
        Anything that would have generated an in-app notification for the bot
        also generates a webhook delivery. Common ones:
      </p>
      <ul>
        <li><code>mention</code> — someone @-mentioned the bot</li>
        <li><code>reply</code> — someone replied to one of the bot's posts</li>
        <li><code>reaction</code> — someone reacted to a post</li>
        <li><code>boost</code> — someone boosted a post</li>
        <li><code>quote</code> — someone quote-posted</li>
        <li><code>follow</code> / <code>follow_request</code> — new follower</li>
        <li><code>poll_ended</code> — a poll the bot ran ended</li>
        <li>Group / page admin events: <code>group_invite</code>, <code>group_application</code>, <code>page_invite</code></li>
      </ul>

      <h3>Payload shape</h3>
      <p>Every request is a JSON object with <code>event</code>, <code>payload</code>, and <code>delivered_at</code>:</p>
      <pre class="code-block">{`{
  "event": "mention",
  "payload": {
    "event": "mention",
    "notification_id": "9d4a…",
    "recipient_id": "<bot identity id>",
    "actor_id": "<user who mentioned the bot>",
    "target_type": "post",
    "target_id": "<post id>",
    "created_at": "2026-05-20T12:34:56.789Z"
  },
  "delivered_at": "2026-05-20T12:34:57.012Z"
}`}</pre>
      <p>
        The bot's webhook only fires for events <em>about the bot</em> — when
        you build the response, fetch the target object (post, account, etc.)
        via the regular API to get the full content.
      </p>

      <h3>Headers we send</h3>
      <ul>
        <li><code>content-type: application/json</code></li>
        <li><code>user-agent: {$instanceName}-Webhook/1.0</code></li>
        <li><code>x-webhook-event</code> — same string as <code>event</code> in the body, for routing without parsing.</li>
        <li><code>x-webhook-signature: sha256=&lt;hex&gt;</code> — HMAC-SHA256 of the raw request body, hex-encoded.</li>
        <li><code>x-webhook-delivery</code> — the delivery row's UUID. Idempotent retries reuse the same value.</li>
      </ul>

      <h3>Verifying the signature</h3>
      <p>
        Recompute <code>hmac_sha256(your_signing_secret, raw_body)</code> on
        receipt and constant-time compare against the value in the
        <code>x-webhook-signature</code> header (strip the <code>sha256=</code>
        prefix first). Reject any request whose signature doesn't match — that's
        either a replay attempt or someone trying to forge events. Example in
        Node:
      </p>
      <pre class="code-block">{`import crypto from 'node:crypto';

const SECRET = process.env.HYBRIDSOCIAL_WEBHOOK_SECRET;

app.post('/webhook', express.raw({ type: '*/*' }), (req, res) => {
  const sigHeader = req.get('x-webhook-signature') || '';
  const got = sigHeader.replace(/^sha256=/, '');
  const expected = crypto
    .createHmac('sha256', SECRET)
    .update(req.body)
    .digest('hex');

  const ok =
    got.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(got), Buffer.from(expected));
  if (!ok) return res.sendStatus(401);

  const body = JSON.parse(req.body);
  // route on body.event ...
  res.sendStatus(200);
});`}</pre>
      <p>
        Pass it a raw body buffer (not parsed JSON) so you sign the exact same
        bytes we did. Most frameworks have a "raw body" middleware for this.
      </p>

      <h3>Retries and delivery guarantees</h3>
      <ul>
        <li>We expect any 2xx status code to mean "delivered" — body content is ignored.</li>
        <li>
          On non-2xx or a network error we retry up to <strong>3 times</strong>
          with backoff: <strong>60 s → 5 min → 30 min</strong>. After the third
          attempt the delivery is marked <code>failed</code> and not retried.
        </li>
        <li>
          Each retry uses the <strong>same</strong> <code>x-webhook-delivery</code>
          header value, so you can deduplicate by that.
        </li>
        <li>
          If you toggle the bot to inactive, pending deliveries pause until you
          re-enable it. Removing the URL outright cancels them.
        </li>
        <li>
          Webhook delivery is <strong>at-least-once</strong>. Treat your handler
          as idempotent — replays on transient retries do happen.
        </li>
      </ul>

      <h3>Auditing recent deliveries</h3>
      <p>
        The Webhook panel on Developer Tools shows the last 25 attempts per bot
        with status, HTTP code, and the error message if any. Use it to confirm
        signature verification is right end-to-end before you put your bot in
        front of users.
      </p>
    </section>

    <section id="endpoints" class="docs-section">
      <h2>API endpoints</h2>
      <p>
        The surface area is large — what follows is a topical map. For a quick
        reference, the API Tester on the
        <a href="/settings/developers">Developer Tools page</a> runs live calls
        against your own credentials.
      </p>

      <div class="endpoint-table">
        <div class="endpoint-row">
          <div class="endpoint-area">Statuses &amp; posts</div>
          <div class="endpoint-paths">
            <code>POST /api/v1/statuses</code>,
            <code>GET /api/v1/statuses/:id</code>,
            <code>DELETE /api/v1/statuses/:id</code>,
            <code>POST /api/v1/statuses/:id/boost</code>,
            <code>POST /api/v1/statuses/:id/react</code>,
            <code>POST /api/v1/statuses/:id/pin</code>,
            <code>POST /api/v1/statuses/:id/bookmark</code>,
            <code>GET /api/v1/statuses/:id/translate</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Timelines</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/timelines/home</code>,
            <code>GET /api/v1/timelines/public</code>,
            <code>GET /api/v1/timelines/trending</code>,
            <code>GET /api/v1/timelines/list/:id</code>,
            <code>GET /api/v1/timelines/group/:id</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Accounts</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/accounts/:id</code>,
            <code>POST /api/v1/accounts/:id/follow</code>,
            <code>POST /api/v1/accounts/:id/unfollow</code>,
            <code>GET /api/v1/accounts/:id/statuses</code>,
            <code>POST /api/v1/accounts/:id/block</code>,
            <code>POST /api/v1/accounts/:id/mute</code>,
            <code>GET /api/v1/accounts/lookup?acct=@user@host</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Search &amp; discovery</div>
          <div class="endpoint-paths">
            <code>GET /api/v2/search</code>,
            <code>GET /api/v1/trends/tags</code>,
            <code>GET /api/v1/trends/statuses</code>,
            <code>GET /api/v1/suggestions</code>,
            <code>GET /api/v1/directory</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Notifications</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/notifications</code>,
            <code>POST /api/v1/notifications/clear</code>,
            <code>POST /api/v1/notifications/:id/dismiss</code>,
            <code>POST /api/v1/push/subscription</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Direct messages</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/conversations</code>,
            <code>POST /api/v1/conversations</code>,
            <code>POST /api/v1/conversations/:id/messages</code>,
            <code>POST /api/v1/conversations/:id/read</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Groups &amp; pages</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/groups</code>,
            <code>POST /api/v1/groups/:id/join</code>,
            <code>POST /api/v1/groups/:id/invite</code>,
            <code>GET /api/v1/groups/:id/applications</code>,
            <code>GET /api/v1/pages</code>,
            <code>POST /api/v1/pages/:id/follow</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Media</div>
          <div class="endpoint-paths">
            <code>POST /api/v1/media</code> (multipart),
            <code>PUT /api/v1/media/:id</code>,
            <code>DELETE /api/v1/media/:id</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Lists &amp; filters</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/lists</code>,
            <code>POST /api/v1/lists</code>,
            <code>POST /api/v1/lists/:id/accounts</code>,
            <code>GET /api/v2/filters</code>,
            <code>POST /api/v2/filters</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Real-time streaming (SSE)</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/streaming/user</code>,
            <code>GET /api/v1/streaming/public</code>,
            <code>GET /api/v1/streaming/hashtag?tag=…</code>,
            <code>GET /api/v1/streaming/list/:id</code>,
            <code>GET /api/v1/streaming/group/:id</code>
          </div>
        </div>

        <div class="endpoint-row">
          <div class="endpoint-area">Instance metadata</div>
          <div class="endpoint-paths">
            <code>GET /api/v1/instance</code>,
            <code>GET /api/v1/custom_emojis</code>,
            <code>GET /.well-known/webfinger?resource=acct:user@host</code>
          </div>
        </div>
      </div>

      <p class="endpoint-footnote">
        Routes that touch federated identities accept the full <code>acct:</code>
        form (<code>@alice@example.social</code>). Routes that take an
        <code>:id</code> always mean the local UUID — use
        <code>/accounts/lookup</code> first to resolve a federated handle to one.
      </p>
    </section>

    <section id="limits" class="docs-section">
      <h2>Rate limits &amp; scopes</h2>

      <h3>Scopes</h3>
      <p>OAuth apps request a subset of these. Bots are issued all four by default.</p>
      <ul>
        <li><code>read</code> — Read timelines, accounts, posts, notifications.</li>
        <li><code>write</code> — Create, edit, delete posts. Upload media. Send DMs.</li>
        <li><code>follow</code> — Follow / unfollow, block / mute, accept follow requests.</li>
        <li><code>push</code> — Manage WebPush subscriptions.</li>
      </ul>

      <h3>Rate limits</h3>
      <p>
        Defaults shown — every value is admin-tunable from the instance settings.
      </p>
      <ul>
        <li><strong>Authenticated requests:</strong> 1200 per window per token.</li>
        <li><strong>Anonymous requests:</strong> 240 per window per IP.</li>
        <li><strong>Federation endpoints:</strong> 1800 per IP.</li>
        <li><strong>Posts per hour:</strong> per-bot override (1–1000) — leave unset for the instance default.</li>
        <li><strong>Maximum bots per user:</strong> 4 by default.</li>
      </ul>
      <p>
        Rate-limit headers are returned on every response. When you hit the limit
        you'll get a <code>429</code> with a <code>Retry-After</code> header in
        seconds. Back off and retry.
      </p>

      <h3>Errors</h3>
      <p>
        All error responses are JSON shaped <code>{`{ "error": "code", … }`}</code>.
        Common codes: <code>401</code> (bad / missing token),
        <code>403</code> (token lacks the required scope or you're not a member /
        admin of the resource), <code>404</code> (resource gone or hidden),
        <code>422</code> (payload validation failed — look at
        <code>details</code>), <code>429</code> (rate-limited).
      </p>
    </section>

    <section id="examples" class="docs-section">
      <h2>Examples</h2>

      <h3>Post a status</h3>
      <pre class="code-block">{`curl -X POST https://YOUR_INSTANCE/api/v1/statuses \\
  -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{"status": "Hello from a bot!", "visibility": "public"}'`}</pre>

      <h3>Stream new home-timeline events</h3>
      <pre class="code-block">curl -N https://YOUR_INSTANCE/api/v1/streaming/user \
  -H "Authorization: Bearer $TOKEN"
# Lines arrive as Server-Sent Events:
#   event: update
#   data: {'{'} ...post... {'}'}</pre>

      <h3>Upload media, then attach it to a post</h3>
      <pre class="code-block">{`MEDIA_ID=$(curl -s -X POST https://YOUR_INSTANCE/api/v1/media \\
  -H "Authorization: Bearer $TOKEN" \\
  -F "file=@photo.jpg" | jq -r .id)

curl -X POST https://YOUR_INSTANCE/api/v1/statuses \\
  -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" \\
  -d "{\\"status\\": \\"with a photo\\", \\"media_ids\\": [\\"$MEDIA_ID\\"]}"`}</pre>

      <h3>Send a DM</h3>
      <pre class="code-block">{`curl -X POST https://YOUR_INSTANCE/api/v1/conversations/$CID/messages \\
  -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{"content": "Hi!"}'`}</pre>

      <h3>Look up a federated user</h3>
      <pre class="code-block">curl "https://YOUR_INSTANCE/api/v1/accounts/lookup?acct=@alice@example.social" \
  -H "Authorization: Bearer $TOKEN"</pre>
    </section>
  </article>
</div>

<style>
  .docs-shell {
    display: grid;
    grid-template-columns: 240px 1fr;
    gap: var(--space-6);
    max-width: 1100px;
    margin: 0 auto;
    padding: var(--space-4);
  }

  @media (max-width: 768px) {
    .docs-shell {
      grid-template-columns: 1fr;
      gap: var(--space-3);
    }
  }

  .docs-sidebar {
    position: sticky;
    top: var(--space-4);
    align-self: start;
    max-height: calc(100vh - var(--space-8));
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  @media (max-width: 768px) {
    .docs-sidebar {
      position: static;
      max-height: none;
      border-block-end: 1px solid var(--color-border);
      padding-block-end: var(--space-3);
    }
  }

  .sidebar-heading {
    margin: 0;
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .sidebar-nav {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .sidebar-item {
    display: block;
    padding: var(--space-2) var(--space-3);
    border: none;
    background: transparent;
    color: var(--color-text-secondary);
    border-radius: var(--radius-md);
    cursor: pointer;
    font: inherit;
    text-align: start;
    transition: background var(--transition-fast), color var(--transition-fast);
    width: 100%;
  }

  .sidebar-item:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .sidebar-item-active {
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-weight: 600;
  }

  .sidebar-cta {
    display: inline-block;
    padding: var(--space-2) var(--space-3);
    color: var(--color-primary);
    font-size: var(--text-sm);
    font-weight: 600;
    text-decoration: none;
    border: 1px solid var(--color-primary);
    border-radius: var(--radius-md);
    text-align: center;
    margin-block-start: var(--space-2);
  }

  .sidebar-cta:hover {
    background: var(--color-primary-soft);
  }

  .docs-content {
    min-width: 0;
  }

  .docs-section {
    scroll-margin-top: var(--space-6);
    padding-block: var(--space-5);
    border-block-end: 1px solid var(--color-border);
  }

  .docs-section:last-child {
    border-block-end: none;
  }

  .docs-section h1 {
    margin: 0 0 var(--space-2) 0;
    font-size: var(--text-2xl);
    color: var(--color-text);
  }

  .docs-section h2 {
    margin: 0 0 var(--space-3) 0;
    font-size: var(--text-xl);
    color: var(--color-text);
  }

  .docs-section h3 {
    margin: var(--space-5) 0 var(--space-2) 0;
    font-size: var(--text-md);
    color: var(--color-text);
  }

  .docs-section p,
  .docs-section li {
    color: var(--color-text);
    line-height: 1.65;
  }

  .docs-section ul,
  .docs-section ol {
    margin: var(--space-2) 0;
    padding-inline-start: var(--space-5);
  }

  .docs-section a {
    color: var(--color-primary);
  }

  .lead {
    font-size: var(--text-md);
    color: var(--color-text-secondary);
  }

  code {
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.92em;
    background: var(--color-surface);
    padding: 1px 6px;
    border-radius: var(--radius-sm);
    color: var(--color-text);
  }

  .code-block {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: var(--space-3);
    margin: var(--space-2) 0;
    overflow-x: auto;
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.85rem;
    line-height: 1.5;
    color: var(--color-text);
    white-space: pre;
  }

  .choice-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-3);
    margin-block-start: var(--space-3);
  }

  @media (max-width: 640px) {
    .choice-grid {
      grid-template-columns: 1fr;
    }
  }

  .choice-card {
    padding: var(--space-4);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
  }

  .choice-card h3 {
    margin: 0 0 var(--space-2) 0;
    color: var(--color-primary);
  }

  .choice-pros {
    margin-block-start: var(--space-2);
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
  }

  .numbered-list {
    list-style: decimal;
  }

  .endpoint-table {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

  .endpoint-row {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: var(--space-3);
    padding: var(--space-3);
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  @media (max-width: 640px) {
    .endpoint-row {
      grid-template-columns: 1fr;
    }
  }

  .endpoint-area {
    font-weight: 600;
    color: var(--color-text);
  }

  .endpoint-paths {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1);
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    line-height: 1.8;
  }

  .endpoint-paths code {
    font-size: 0.85em;
  }

  .endpoint-footnote {
    margin-block-start: var(--space-3);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }
</style>
