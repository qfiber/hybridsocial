<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import type { Post } from '$lib/api/types.js';
  import { getPost, getPostContext } from '$lib/api/statuses.js';
  import PostCard from '$lib/components/post/PostCard.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let post = $state<Post | null>(null);
  let ancestors = $state<Post[]>([]);
  let descendants = $state<Post[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  let postId = $derived(page.params.id);

  onMount(async () => {
    try {
      const [p, context] = await Promise.all([
        getPost(postId),
        getPostContext(postId)
      ]);
      post = p;
      ancestors = context.ancestors || [];
      descendants = context.descendants || [];
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load post';
    } finally {
      loading = false;
    }
  });

  function goBack() {
    if (window.history.length > 1) {
      window.history.back();
    } else {
      window.location.href = '/home';
    }
  }
</script>

<svelte:head>
  <title>{post ? `Post by ${post.account.display_name || post.account.handle}` : 'Post'} - HybridSocial</title>
</svelte:head>

<div class="post-detail-page">
  <div class="page-header">
    <button type="button" class="back-btn" onclick={goBack} aria-label="Go back">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <polyline points="15 18 9 12 15 6"/>
      </svg>
      <span>Back</span>
    </button>
    <h1 class="page-title">Post</h1>
  </div>

  {#if loading}
    <div class="page-loading">
      <Spinner />
    </div>
  {:else if error}
    <div class="page-error">
      <p>{error}</p>
      <button type="button" class="btn btn-secondary" onclick={goBack}>Go back</button>
    </div>
  {:else if post}
    <div class="thread">
      {#if ancestors.length > 0}
        <div class="thread-ancestors">
          {#each ancestors as ancestor (ancestor.id)}
            <PostCard post={ancestor} compact />
          {/each}
        </div>
      {/if}

      <div class="thread-main">
        <PostCard {post} detail />
      </div>

      {#if descendants.length > 0}
        <div class="thread-replies">
          <h2 class="replies-heading">Replies</h2>
          {#each descendants as reply (reply.id)}
            <PostCard post={reply} />
          {/each}
        </div>
      {/if}
    </div>
  {:else}
    <div class="page-error">
      <p>Post not found</p>
      <button type="button" class="btn btn-secondary" onclick={goBack}>Go back</button>
    </div>
  {/if}
</div>

<style>
  .post-detail-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding-block-end: var(--space-4);
  }

  .back-btn {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    background: none;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    font-size: var(--text-sm);
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-md);
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .back-btn:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .page-loading,
  .page-error {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-4);
    padding: var(--space-16);
    color: var(--color-text-tertiary);
  }

  .thread {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .thread-ancestors {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    opacity: 0.85;
    border-inline-start: 2px solid var(--color-border);
    padding-inline-start: var(--space-3);
  }

  .thread-main {
    position: relative;
  }

  .thread-replies {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-start: var(--space-2);
  }

  .replies-heading {
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
    padding-block: var(--space-2);
  }
</style>
