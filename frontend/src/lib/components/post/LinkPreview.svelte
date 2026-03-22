<script lang="ts">
  let {
    url,
    title = '',
    description = '',
    image = '',
    siteName = '',
  }: {
    url: string;
    title?: string;
    description?: string;
    image?: string;
    siteName?: string;
  } = $props();
</script>

<a
  href={url}
  class="link-preview"
  target="_blank"
  rel="noopener noreferrer"
  onclick={(e) => e.stopPropagation()}
>
  {#if image}
    <div class="link-preview-image">
      <img src={image} alt="" loading="lazy" />
    </div>
  {/if}
  <div class="link-preview-body">
    {#if siteName}
      <span class="link-preview-site">{siteName}</span>
    {/if}
    {#if title}
      <span class="link-preview-title">{title}</span>
    {/if}
    {#if description}
      <span class="link-preview-desc">{description}</span>
    {/if}
  </div>
</a>

<style>
  .link-preview {
    display: flex;
    flex-direction: column;
    margin-block-start: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    overflow: hidden;
    text-decoration: none;
    color: inherit;
    transition: background-color var(--transition-fast);
  }

  .link-preview:hover {
    background: var(--color-bg-secondary);
    text-decoration: none;
  }

  .link-preview-image {
    width: 100%;
    aspect-ratio: 2 / 1;
    overflow: hidden;
    background: var(--color-bg-tertiary);
  }

  .link-preview-image img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .link-preview-body {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    padding: var(--space-3);
  }

  .link-preview-site {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.02em;
  }

  .link-preview-title {
    font-size: var(--text-sm);
    font-weight: var(--font-semibold);
    color: var(--color-text);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .link-preview-desc {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
</style>
