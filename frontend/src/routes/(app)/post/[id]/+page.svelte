<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import type { Post } from '$lib/api/types.js';
  import { getPost, getPostContext } from '$lib/api/statuses.js';
  import PostCard from '$lib/components/post/PostCard.svelte';
  import ThreadedReplies from '$lib/components/post/ThreadedReplies.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let post = $state<Post | null>(null);
  let ancestors = $state<Post[]>([]);
  let descendants = $state<Post[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);

  let postId = $derived(page.params.id!);

  async function loadThread() {
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
  }

  onMount(() => {
    loadThread();

    // Listen for new replies (optimistic)
    function handleNewPost(e: Event) {
      const newPost = (e as CustomEvent<Post>).detail;
      if (!newPost) return;

      const isReplyToThisThread =
        newPost.parent_id === postId ||
        newPost.root_id === postId ||
        descendants.some(d => d.id === newPost.parent_id);

      if (isReplyToThisThread) {
        if (!descendants.some(d => d.id === newPost.id)) {
          descendants = [...descendants, newPost];
        }
        if (post && newPost.parent_id === postId) {
          post.reply_count = (post.reply_count || 0) + 1;
        }
      }
    }

    function handlePostDeleted(e: Event) {
      const { id } = (e as CustomEvent).detail;
      if (id) {
        descendants = descendants.filter(d => d.id !== id);
      }
    }

    window.addEventListener('new-post', handleNewPost);
    window.addEventListener('post-deleted', handlePostDeleted);

    return () => {
      window.removeEventListener('new-post', handleNewPost);
      window.removeEventListener('post-deleted', handlePostDeleted);
    };
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
      <span class="material-symbols-outlined back-icon">arrow_back</span>
    </button>
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
          <ThreadedReplies {descendants} rootPostId={post.id} />
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
    padding-block-end: var(--space-2);
  }

  .back-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    background: none;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    border-radius: 50%;
    transition: background 150ms ease, color 150ms ease;
  }

  .back-btn:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .back-icon {
    font-size: 22px;
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
    gap: 0;
    position: relative;
    padding-inline-start: 20px;
  }

  /* Vertical connector line running down the ancestor chain */
  .thread-ancestors::after {
    content: '';
    position: absolute;
    inset-inline-start: 8px;
    top: 40px;
    bottom: -8px;
    width: 2px;
    background: var(--color-border);
  }

  .thread-ancestors :global(.post-card) {
    opacity: 0.75;
    box-shadow: none;
    border: 1px solid var(--color-border);
    margin-block: 2px;
  }

  .thread-ancestors :global(.post-card:hover) {
    opacity: 1;
  }

  .thread-main {
    position: relative;
  }

  .thread-replies {
    display: flex;
    flex-direction: column;
  }
</style>
