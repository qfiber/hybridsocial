<script lang="ts">
  let {
    trending = [],
    suggestions = []
  }: {
    trending?: { tag: string; count: number }[];
    suggestions?: { handle: string; display_name: string; avatar_url: string | null }[];
  } = $props();
</script>

<aside class="right-sidebar">
  <section class="sidebar-section">
    <h3 class="section-title">Trending</h3>
    {#if trending.length > 0}
      <ul class="trending-list">
        {#each trending as item (item.tag)}
          <li>
            <a href="/explore?q=%23{encodeURIComponent(item.tag)}" class="trending-item">
              <span class="trending-tag">#{item.tag}</span>
              <span class="trending-count">{item.count} posts</span>
            </a>
          </li>
        {/each}
      </ul>
    {:else}
      <p class="empty-text">No trending topics yet.</p>
    {/if}
  </section>

  <section class="sidebar-section">
    <h3 class="section-title">Who to follow</h3>
    {#if suggestions.length > 0}
      <ul class="suggestions-list">
        {#each suggestions as person (person.handle)}
          <li>
            <a href="/@{person.handle}" class="suggestion-item">
              <div class="suggestion-avatar">
                {#if person.avatar_url}
                  <img src={person.avatar_url} alt={person.display_name} class="suggestion-img" />
                {:else}
                  <span class="suggestion-initial">{person.display_name.charAt(0).toUpperCase()}</span>
                {/if}
              </div>
              <div class="suggestion-info">
                <span class="suggestion-name">{person.display_name}</span>
                <span class="suggestion-handle">@{person.handle}</span>
              </div>
            </a>
          </li>
        {/each}
      </ul>
    {:else}
      <p class="empty-text">No suggestions right now.</p>
    {/if}
  </section>

  <section class="sidebar-footer">
    <nav class="footer-links" aria-label="Footer">
      <a href="/about" class="footer-link">About</a>
      <span class="footer-dot" aria-hidden="true">&middot;</span>
      <a href="/donate" class="footer-link">Support</a>
    </nav>
    <p class="footer-text">HybridSocial &middot; Decentralized Social</p>
  </section>
</aside>

<style>
  .right-sidebar {
    position: sticky;
    top: var(--header-height);
    height: calc(100vh - var(--header-height));
    padding: var(--space-4);
    overflow-y: auto;
  }

  .sidebar-section {
    margin-block-end: var(--space-6);
    background: var(--color-surface);
    border-radius: var(--radius-xl);
    padding: var(--space-4);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-3);
  }

  .trending-list,
  .suggestions-list {
    display: flex;
    flex-direction: column;
  }

  .trending-item {
    display: flex;
    flex-direction: column;
    padding: var(--space-2) 0;
    text-decoration: none;
    color: var(--color-text);
    transition: color var(--transition-fast);
  }

  .trending-item:hover {
    text-decoration: none;
    color: var(--color-primary);
  }

  .trending-tag {
    font-weight: 600;
    font-size: var(--text-sm);
  }

  .trending-count {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .suggestion-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) 0;
    text-decoration: none;
    color: var(--color-text);
  }

  .suggestion-item:hover {
    text-decoration: none;
  }

  .suggestion-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: var(--color-primary-soft);
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .suggestion-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .suggestion-initial {
    font-weight: 600;
    color: var(--color-primary);
    font-size: var(--text-sm);
  }

  .suggestion-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .suggestion-name {
    font-size: var(--text-sm);
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .suggestion-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .sidebar-footer {
    padding: 0;
  }

  .footer-links {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    margin-block-end: var(--space-2);
  }

  .footer-link {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-decoration: none;
  }

  .footer-link:hover {
    color: var(--color-primary);
    text-decoration: underline;
  }

  .footer-dot {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .footer-text {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  @media (max-width: 1200px) {
    .right-sidebar {
      display: none;
    }
  }
</style>
