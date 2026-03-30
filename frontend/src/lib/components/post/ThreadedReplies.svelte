<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import PostCard from './PostCard.svelte';

  let {
    descendants,
    rootPostId,
    maxDepth = 4,
  }: {
    descendants: Post[];
    rootPostId: string;
    maxDepth?: number;
  } = $props();

  interface ReplyNode {
    post: Post;
    children: ReplyNode[];
    depth: number;
  }

  function buildTree(posts: Post[], rootId: string): ReplyNode[] {
    const map = new Map<string, ReplyNode>();
    const roots: ReplyNode[] = [];

    for (const post of posts) {
      if (post.tombstone) continue;
      map.set(post.id, { post, children: [], depth: 0 });
    }

    for (const post of posts) {
      if (post.tombstone) continue;
      const node = map.get(post.id)!;
      const parentId = post.parent_id;

      if (parentId && map.has(parentId)) {
        map.get(parentId)!.children.push(node);
      } else {
        roots.push(node);
      }
    }

    function setDepths(nodes: ReplyNode[], depth: number) {
      for (const node of nodes) {
        node.depth = depth;
        setDepths(node.children, depth + 1);
      }
    }
    setDepths(roots, 0);
    return roots;
  }

  let tree = $derived(buildTree(descendants, rootPostId));

  let expandedChildren = $state<Record<string, boolean>>({});

  function toggleChildren(postId: string) {
    expandedChildren[postId] = !expandedChildren[postId];
  }

  // Inline reply for root-level only
  let replyContent = $state('');
  let replySending = $state(false);

  async function sendReply() {
    if (!replyContent.trim() || replySending) return;
    replySending = true;
    try {
      const result = await api.post<Post>('/api/v1/statuses', {
        content: replyContent,
        parent_id: rootPostId,
        visibility: 'public',
      });
      replyContent = '';
      window.dispatchEvent(new CustomEvent('new-post', { detail: result }));
    } catch { /* */ }
    finally { replySending = false; }
  }

  function countAllChildren(node: ReplyNode): number {
    let count = node.children.length;
    for (const child of node.children) count += countAllChildren(child);
    return count;
  }
</script>

<div class="threaded-replies">
  {#each tree as node, i (node.post.id)}
    {@render replyNode(node, i < tree.length - 1)}
  {/each}

  <!-- Inline reply bar -->
  <div class="inline-reply-bar">
    <input
      type="text"
      class="inline-reply-input"
      placeholder="Write a reply..."
      bind:value={replyContent}
      onkeydown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendReply(); } }}
    />
    <button type="button" class="inline-reply-send" onclick={sendReply} disabled={replySending || !replyContent.trim()}>
      <span class="material-symbols-outlined">send</span>
    </button>
  </div>
</div>

{#snippet replyNode(node: ReplyNode, hasSiblingsBelow: boolean)}
  {@const hasVisibleChildren = node.children.length > 0 && (node.depth < maxDepth || expandedChildren[node.post.id])}
  <div class="reply-node" style="--indent: {node.depth}">
    <!-- Connector gutter -->
    <div class="reply-gutter">
      <!-- Vertical line from parent, curving into this reply (L-shape) -->
      {#if node.depth > 0}
        <div class="connector-l">
          <div class="connector-l-vert"></div>
          <div class="connector-l-horiz"></div>
        </div>
      {/if}
      <!-- Continuation line passing through to siblings below -->
      {#if node.depth > 0 && hasSiblingsBelow}
        <div class="connector-pass"></div>
      {/if}
    </div>

    <!-- Reply card + children -->
    <div class="reply-content">
      <PostCard post={node.post} />

      <!-- Collapsed children -->
      {#if node.children.length > 0 && node.depth >= maxDepth && !expandedChildren[node.post.id]}
        <button type="button" class="view-replies-btn" onclick={() => toggleChildren(node.post.id)}>
          View {countAllChildren(node)} {countAllChildren(node) === 1 ? 'reply' : 'replies'}
        </button>
      {/if}

      <!-- Children -->
      {#if hasVisibleChildren}
        <div class="reply-children">
          {#each node.children as child, i (child.post.id)}
            {@render replyNode(child, i < node.children.length - 1)}
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/snippet}

<style>
  .threaded-replies {
    display: flex;
    flex-direction: column;
  }

  /* ---- Reply node ---- */
  .reply-node {
    display: flex;
    gap: 0;
    position: relative;
  }

  /* ---- Gutter (connector lines) ---- */
  .reply-gutter {
    flex-shrink: 0;
    width: 24px;
    position: relative;
  }

  /* L-shaped connector: vertical part comes down from parent, horizontal goes right to card */
  .connector-l {
    position: absolute;
    inset-inline-start: 11px;
    top: 0;
    width: 13px;
    height: 24px;
  }

  .connector-l-vert {
    position: absolute;
    inset-inline-start: 0;
    top: 0;
    width: 2px;
    height: 14px;
    background: var(--color-border);
    border-radius: 0 0 0 0;
  }

  .connector-l-horiz {
    position: absolute;
    inset-inline-start: 0;
    top: 12px;
    width: 100%;
    height: 2px;
    background: var(--color-border);
    border-start-end-radius: 0;
    border-end-start-radius: 6px;
  }

  /* Vertical pass-through line for siblings below */
  .connector-pass {
    position: absolute;
    inset-inline-start: 11px;
    top: 0;
    bottom: 0;
    width: 2px;
    background: var(--color-border);
  }

  /* ---- Reply content area ---- */
  .reply-content {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  /* Scale down reply cards to feel like subcards */
  .reply-content > :global(.post-card) {
    border-radius: 12px;
    margin-block: 2px;
    padding: 10px 12px;
    border: 1px solid var(--color-border);
    background: var(--color-surface-container-lowest);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06), 0 0 0 1px rgba(0, 0, 0, 0.02);
  }

  .reply-content > :global(.post-card .avatar-img),
  .reply-content > :global(.post-card .avatar-placeholder) {
    width: 28px !important;
    height: 28px !important;
    font-size: 0.7rem !important;
  }

  .reply-content > :global(.post-card .post-display-name) {
    font-size: 0.8125rem;
  }

  .reply-content > :global(.post-card .post-handle),
  .reply-content > :global(.post-card .post-time),
  .reply-content > :global(.post-card .post-edited),
  .reply-content > :global(.post-card .post-dot) {
    font-size: 0.6875rem;
  }

  .reply-content > :global(.post-card .post-body) {
    margin-block-start: 6px;
  }

  .reply-content > :global(.post-card .post-content) {
    font-size: 0.875rem;
  }

  .reply-content > :global(.post-card .post-actions-divider) {
    margin-block: 8px;
  }

  .reply-content > :global(.post-card .action-icon) {
    font-size: 17px;
  }

  .reply-content > :global(.post-card .action-btn) {
    padding: 4px 6px;
    font-size: 0.75rem;
  }

  .reply-content > :global(.post-card .post-reply-indicator) {
    font-size: 0.6875rem;
  }

  /* ---- Children ---- */
  .reply-children {
    display: flex;
    flex-direction: column;
    padding-inline-start: 16px;
    position: relative;
  }

  /* Vertical line running alongside all children */
  .reply-children::before {
    content: '';
    position: absolute;
    inset-inline-start: -1px;
    top: 0;
    bottom: 24px;
    width: 2px;
    background: var(--color-border);
  }

  /* ---- View replies link ---- */
  .view-replies-btn {
    background: none;
    border: none;
    color: var(--color-primary);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    padding: 6px 0;
    text-align: start;
    margin-inline-start: 4px;
  }

  .view-replies-btn:hover {
    text-decoration: underline;
  }

  /* ---- Inline reply bar ---- */
  .inline-reply-bar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 16px;
    margin-block-start: 8px;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
  }

  .inline-reply-input {
    flex: 1;
    padding: 10px 16px;
    border: 1px solid var(--color-border);
    border-radius: 22px;
    background: var(--color-surface);
    color: var(--color-text);
    font-size: 0.9375rem;
    outline: none;
    transition: border-color 150ms ease, box-shadow 150ms ease;
  }

  .inline-reply-input:focus {
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft, rgba(0, 128, 128, 0.1));
  }

  .inline-reply-send {
    background: var(--color-primary);
    border: none;
    color: white;
    cursor: pointer;
    padding: 8px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: opacity 150ms ease;
  }

  .inline-reply-send:hover:not(:disabled) {
    opacity: 0.9;
  }

  .inline-reply-send:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .inline-reply-send .material-symbols-outlined {
    font-size: 20px;
  }
</style>
