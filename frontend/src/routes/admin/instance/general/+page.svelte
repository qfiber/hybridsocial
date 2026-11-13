<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as ti } from '$lib/utils/i18n.js';
  import { getAdminSettings, updateAdminSettings } from '$lib/api/admin.js';
  import AdminPage from '$lib/components/admin/AdminPage.svelte';
  import SettingsSection from '$lib/components/admin/SettingsSection.svelte';
  import SettingRow from '$lib/components/admin/SettingRow.svelte';
  import SaveBar from '$lib/components/admin/SaveBar.svelte';

  // These identity fields live in the generic Config store (keys below),
  // not the theme_* namespace, and are written through the settings API.
  type Form = { instance_name: string; instance_description: string; contact_email: string };
  const empty: Form = { instance_name: '', instance_description: '', contact_email: '' };

  let saved = $state<Form>({ ...empty });
  let form = $state<Form>({ ...empty });
  let loading = $state(true);
  let saving = $state(false);

  let dirty = $derived(
    (Object.keys(form) as (keyof Form)[]).some((k) => form[k] !== saved[k]),
  );

  async function load() {
    try {
      const settings = await getAdminSettings();
      const map = new Map(settings.map((s) => [s.key, s.value]));
      const str = (k: keyof Form) => {
        const v = map.get(k);
        return typeof v === 'string' ? v : '';
      };
      saved = {
        instance_name: str('instance_name'),
        instance_description: str('instance_description'),
        contact_email: str('contact_email'),
      };
      form = { ...saved };
    } catch {
      addToast(ti('admin_general.load_error'), 'error');
    } finally {
      loading = false;
    }
  }

  async function save() {
    saving = true;
    try {
      await updateAdminSettings(
        (Object.keys(form) as (keyof Form)[]).map((key) => ({ key, value: form[key] })),
      );
      saved = { ...form };
      addToast(ti('admin_general.saved'), 'success');
    } catch {
      addToast(ti('admin_general.save_error'), 'error');
    } finally {
      saving = false;
    }
  }

  function discard() {
    form = { ...saved };
  }

  onMount(load);
</script>

<AdminPage title={$t('admin_general.title')} description={$t('admin_general.description')} width="narrow">
  {#if loading}
    <p class="general-loading">{$t('admin_shell.loading')}</p>
  {:else}
    <SettingsSection title={$t('admin_general.identity_title')} description={$t('admin_general.identity_description')}>
      <SettingRow
        label={$t('admin_general.name_label')}
        help={$t('admin_general.name_help')}
        labelFor="instance-name"
        layout="stacked"
      >
        <input id="instance-name" type="text" class="input" maxlength="100" bind:value={form.instance_name} />
      </SettingRow>

      <SettingRow
        label={$t('admin_general.description_label')}
        help={$t('admin_general.description_help')}
        labelFor="instance-desc"
        layout="stacked"
      >
        <textarea id="instance-desc" class="textarea" rows="4" bind:value={form.instance_description}></textarea>
      </SettingRow>
    </SettingsSection>

    <SettingsSection title={$t('admin_general.contact_title')} description={$t('admin_general.contact_description')}>
      <SettingRow
        label={$t('admin_general.email_label')}
        help={$t('admin_general.email_help')}
        labelFor="contact-email"
        layout="stacked"
      >
        <input
          id="contact-email"
          type="email"
          class="input"
          bind:value={form.contact_email}
          placeholder="admin@example.com"
        />
      </SettingRow>
    </SettingsSection>

    <SaveBar {dirty} {saving} onsave={save} ondiscard={discard} />
  {/if}
</AdminPage>

<style>
  .general-loading {
    margin: 0;
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }
</style>
