<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import PostCard from './PostCard.svelte';
  import { t } from '$lib/stores/i18n.js';

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

  // Everything under a node — what the "show replies" button reveals (it
  // opens EXPAND_STEP more *levels*, so the old "View next 5 replies" label
  // rarely matched what appeared).
  function countDescendants(node: ReplyNode): number {
    return node.children.reduce((sum, child) => sum + 1 + countDescendants(child), 0);
  }

  const EXPAND_STEP = 5;

  let expandedExtra = $state<Record<string, number>>({});

  function expandMore(postId: string) {
    expandedExtra[postId] = (expandedExtra[postId] ?? 0) + EXPAND_STEP;
  }
</script>

<div class="threaded-replies">
  {#each tree as node, i (node.post.id)}
    {@render replyNode(node, i < tree.length - 1, maxDepth)}
  {/each}
</div>

{#snippet replyNode(node: ReplyNode, hasSiblingsBelow: boolean, budget: number)}
  {@const localBudget = Math.max(budget, node.depth + (expandedExtra[node.post.id] ?? 0))}
  {@const hasVisibleChildren = node.children.length > 0 && node.depth < localBudget}
  {@const isClamped = node.depth > maxDepth}
  <div
    class="reply-node"
    class:reply-node--clamped={isClamped}
  >
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

      <!-- Expand-by-5 button when we've hit the visible-depth budget -->
      {#if node.children.length > 0 && node.depth >= localBudget}
        {@const hidden = countDescendants(node)}
        <button type="button" class="view-replies-btn" onclick={() => expandMore(node.post.id)}>
          <span class="material-symbols-outlined view-replies-icon" aria-hidden="true">forum</span>
          {hidden === 1 ? $t('thread.show_replies_one') : $t('thread.show_replies_other', { count: hidden })}
        </button>
      {/if}

      <!-- Children -->
      {#if hasVisibleChildren}
        <div class="reply-children">
          {#each node.children as child, i (child.post.id)}
            {@render replyNode(child, i < node.children.length - 1, localBudget)}
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
    width: 18px;
    position: relative;
  }

  /* Beyond maxDepth, drop the gutter so replies render flush with the maxDepth column. */
  .reply-node--clamped > .reply-gutter {
    display: none;
  }

  /* L-shaped connector: vertical part comes down from parent, horizontal goes right to card */
  .connector-l {
    position: absolute;
    inset-inline-start: 8px;
    top: 0;
    width: 10px;
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
    inset-inline-start: 8px;
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

  /* ---- Children ---- Indent lives entirely in each node's .reply-gutter. */
  .reply-children {
    display: flex;
    flex-direction: column;
    padding-inline-start: 0;
    position: relative;
  }

  /* ---- View replies link ---- */
  /* A clear pill button rather than a bare text link: easy to spot at the
     end of a long thread and a full-size tap target on touch. */
  .view-replies-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    align-self: flex-start;
    min-height: 40px;
    margin-block: var(--space-2);
    margin-inline-start: 4px;
    padding: var(--space-2) var(--space-4);
    border: 1px solid color-mix(in srgb, var(--color-primary) 35%, transparent);
    border-radius: 9999px;
    background: color-mix(in srgb, var(--color-primary) 10%, transparent);
    color: var(--color-primary);
    font: inherit;
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: background var(--transition-fast), border-color var(--transition-fast);
  }

  .view-replies-btn:hover {
    background: color-mix(in srgb, var(--color-primary) 18%, transparent);
    border-color: color-mix(in srgb, var(--color-primary) 55%, transparent);
  }

  .view-replies-btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .view-replies-icon {
    font-size: 18px;
  }

  @media (pointer: coarse) {
    .view-replies-btn {
      min-height: 44px;
    }
  }

</style>
