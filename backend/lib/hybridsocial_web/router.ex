defmodule HybridsocialWeb.Router do
  use HybridsocialWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug HybridsocialWeb.Plugs.IpBan
    plug HybridsocialWeb.Plugs.RateLimiter
  end

  pipeline :authenticated do
    plug HybridsocialWeb.Plugs.Auth
    plug HybridsocialWeb.Plugs.RequireAuth
  end

  pipeline :optional_auth do
    plug HybridsocialWeb.Plugs.Auth
  end

  pipeline :rate_limited do
    plug HybridsocialWeb.Plugs.RateLimiter
  end

  pipeline :admin do
    plug HybridsocialWeb.Plugs.Auth
    plug HybridsocialWeb.Plugs.RequireAuth
    plug HybridsocialWeb.Plugs.RequireAdmin
  end

  pipeline :sse do
    plug :accepts, ["json", "event-stream"]
    plug HybridsocialWeb.Plugs.RateLimiter
  end

  # Public auth endpoints (no authentication required)
  scope "/api/v1/auth", HybridsocialWeb.Api.V1 do
    pipe_through :api

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
    post "/confirm", AuthController, :confirm
    post "/2fa/login", AuthController, :login_with_otp
    post "/password/reset", AuthController, :password_reset
    post "/password/change", AuthController, :password_change
    get "/pow_challenge", AuthController, :pow_challenge

    # Passwordless login with security key (public — no auth required)
    post "/webauthn/login/challenge", AuthController, :webauthn_login_challenge
    post "/webauthn/login/verify", AuthController, :webauthn_login_verify
  end

  # Authenticated auth endpoints
  scope "/api/v1/auth", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/logout", AuthController, :logout
    get "/me", AuthController, :me

    # Active sessions
    get "/sessions", SessionController, :index
    delete "/sessions/:id", SessionController, :delete
    post "/sessions/revoke_others", SessionController, :delete_others
    post "/2fa/setup", AuthController, :setup_2fa
    post "/2fa/verify", AuthController, :verify_2fa
    delete "/2fa", AuthController, :disable_2fa

    # WebAuthn / Security Keys
    post "/webauthn/register/challenge", AuthController, :webauthn_register_challenge
    post "/webauthn/register/verify", AuthController, :webauthn_register_verify
    post "/webauthn/authenticate/challenge", AuthController, :webauthn_auth_challenge
    post "/webauthn/authenticate/verify", AuthController, :webauthn_auth_verify
    get "/webauthn/credentials", AuthController, :webauthn_list
    delete "/webauthn/credentials/:id", AuthController, :webauthn_delete
  end

  # Authenticated account endpoints
  scope "/api/v1/accounts", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    patch "/update_credentials", AccountController, :update
    delete "/delete", AccountController, :delete

    # Relationships query
    get "/relationships", AccountController, :relationships

    # Social actions
    post "/:id/follow", AccountController, :follow
    post "/:id/unfollow", AccountController, :unfollow
    post "/:id/block", AccountController, :block
    post "/:id/unblock", AccountController, :unblock
    post "/:id/mute", AccountController, :mute
    post "/:id/unmute", AccountController, :unmute
    post "/:id/mute_boosts", AccountController, :mute_boosts
    post "/:id/unmute_boosts", AccountController, :unmute_boosts

    # Actor migration
    post "/migrate", AccountController, :migrate
    post "/also_known_as", AccountController, :also_known_as
    delete "/also_known_as", AccountController, :remove_alias

    # Follow requests
    get "/follow_requests", AccountController, :follow_requests
    post "/follow_requests/:id/authorize", AccountController, :authorize_follow
    post "/follow_requests/:id/reject", AccountController, :reject_follow

    # User content filters
    get "/filters", AccountController, :list_filters
    post "/filters", AccountController, :create_filter
    put "/filters/:id", AccountController, :update_filter
    delete "/filters/:id", AccountController, :delete_filter

    # User-level domain blocks
    get "/domain_blocks", AccountController, :domain_blocks
    post "/domain_blocks", AccountController, :block_domain
    delete "/domain_blocks", AccountController, :unblock_domain

    # Change email
    post "/change_email", AccountController, :change_email

    # Blocks, mutes, favourites lists
    get "/blocks", AccountController, :blocked_accounts
    get "/mutes", AccountController, :muted_accounts
    get "/favourites", AccountController, :favourited_posts

    # Suggested users
    get "/suggestions", AccountController, :suggestions

    # Drive (media file management)
    get "/drive/folders", AccountController, :drive_folders
    post "/drive/folders", AccountController, :create_drive_folder
    put "/drive/folders/:id", AccountController, :rename_drive_folder
    delete "/drive/folders/:id", AccountController, :delete_drive_folder
    get "/drive/files", AccountController, :drive_files
    post "/drive/files/move", AccountController, :move_drive_files
    post "/drive/files/delete", AccountController, :delete_drive_files
    get "/drive/files/find", AccountController, :find_by_hash
    get "/drive/usage", AccountController, :drive_usage

    # Crypto donation addresses
    get "/crypto_addresses", AccountController, :list_crypto_addresses
    post "/crypto_addresses", AccountController, :set_crypto_address
    delete "/crypto_addresses/:coin", AccountController, :remove_crypto_address

    # Excerpts (keyword-filtered feeds)
    get "/excerpts", AccountController, :list_excerpts
    post "/excerpts", AccountController, :create_excerpt
    get "/excerpts/:id", AccountController, :show_excerpt
    get "/excerpts/:id/feed", AccountController, :excerpt_feed
    put "/excerpts/:id", AccountController, :update_excerpt
    delete "/excerpts/:id", AccountController, :delete_excerpt

    # Followed hashtags
    get "/followed_tags", AccountController, :followed_tags
    post "/followed_tags", AccountController, :follow_tag
    delete "/followed_tags/:name", AccountController, :unfollow_tag
  end

  # Public account endpoints (optional auth for visibility filtering)
  scope "/api/v1/accounts", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/lookup", AccountController, :lookup
    get "/:id/followers", AccountController, :followers
    get "/:id/following", AccountController, :following
    get "/:id/statuses", AccountController, :statuses
    get "/:id/familiar_followers", AccountController, :familiar_followers
    get "/:id/crypto_addresses", AccountController, :public_crypto_addresses
    get "/:id", AccountController, :show
  end

  # Media upload (authenticated)
  scope "/api/v1/media", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", MediaController, :create
    put "/:id", MediaController, :update
  end

  # Media show (public)
  scope "/api/v1/media", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/:id", MediaController, :show
  end

  # OAuth app management (authenticated)
  scope "/api/v1/apps", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", OAuthController, :create_app
    post "/with_token", OAuthController, :create_app_with_token
    get "/", OAuthController, :list_apps
    delete "/:id", OAuthController, :delete_app
  end

  # OAuth authorization (authenticated)
  scope "/oauth", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/authorize", OAuthController, :authorize
  end

  # OAuth token exchange and revocation (public)
  scope "/oauth", HybridsocialWeb.Api.V1 do
    pipe_through :api

    post "/token", OAuthController, :token
    post "/revoke", OAuthController, :revoke
  end

  # Authenticated status endpoints
  scope "/api/v1/statuses", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", StatusController, :create
    put "/:id", StatusController, :update
    delete "/:id", StatusController, :delete

    post "/:id/translate", StatusController, :translate
    get "/:id/reactions", StatusController, :reactions
    post "/:id/react", StatusController, :react
    delete "/:id/react", StatusController, :unreact

    post "/:id/boost", StatusController, :boost
    delete "/:id/boost", StatusController, :unboost

    post "/:id/pin", StatusController, :pin
    delete "/:id/pin", StatusController, :unpin

    post "/:id/view", StatusController, :view

    post "/:id/bookmark", BookmarkController, :create
    delete "/:id/bookmark", BookmarkController, :delete

    post "/:id/mute", StatusController, :mute_post
    delete "/:id/mute", StatusController, :unmute_post
  end

  # Bookmarks (authenticated)
  scope "/api/v1/bookmarks", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", BookmarkController, :index
  end

  # Polls (authenticated)
  scope "/api/v1/polls", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/:id", PollController, :show
    post "/:id/votes", PollController, :vote
  end

  # Public status endpoints (optional auth for visibility filtering)
  scope "/api/v1/statuses", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/:id", StatusController, :show
    get "/:id/context", StatusController, :context
    get "/:id/history", StatusController, :history
  end

  # Lists (authenticated)
  scope "/api/v1/lists", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", ListController, :index
    post "/", ListController, :create
    get "/:id", ListController, :show
    patch "/:id", ListController, :update
    delete "/:id", ListController, :delete
    get "/:id/accounts", ListController, :accounts
    post "/:id/accounts", ListController, :add_accounts
    delete "/:id/accounts", ListController, :remove_accounts
  end

  # Authenticated timeline endpoints
  scope "/api/v1/timelines", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/home", TimelineController, :home
    get "/list/:id", TimelineController, :list
  end

  # Public timeline endpoints (optional auth)
  scope "/api/v1/timelines", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/public", TimelineController, :public
    get "/global", TimelineController, :global
    get "/streams", TimelineController, :streams
    get "/tag/:hashtag", TimelineController, :hashtag
  end

  # Group timeline (authenticated)
  scope "/api/v1/timelines", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/group/:id", TimelineController, :group
  end

  # Notifications (authenticated)
  scope "/api/v1/notifications", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", NotificationController, :index
    post "/clear", NotificationController, :clear
    get "/:id", NotificationController, :show
    post "/:id/read", NotificationController, :mark_read
    delete "/:id", NotificationController, :dismiss
  end

  # Push notifications (authenticated)
  scope "/api/v1/push", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/subscription", PushController, :create
    get "/subscription", PushController, :show
    delete "/subscription", PushController, :delete
    get "/vapid_key", PushController, :vapid_key
  end

  # Notification preferences (authenticated)
  scope "/api/v1/notification_preferences", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", NotificationController, :preferences
    patch "/", NotificationController, :update_preferences
  end

  # Groups (authenticated)
  scope "/api/v1/groups", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", GroupController, :create
    get "/", GroupController, :index
    get "/:id", GroupController, :show
    patch "/:id", GroupController, :update
    delete "/:id", GroupController, :delete

    post "/:id/join", GroupController, :join
    post "/:id/leave", GroupController, :leave
    get "/:id/members", GroupController, :members
    post "/:id/invite", GroupController, :invite

    get "/:id/applications", GroupController, :applications
    post "/:id/applications/:aid/approve", GroupController, :approve_application
    post "/:id/applications/:aid/reject", GroupController, :reject_application

    patch "/:id/members/:mid", GroupController, :update_member
    delete "/:id/members/:mid", GroupController, :remove_member

    get "/:id/screening", GroupController, :screening
    patch "/:id/screening", GroupController, :update_screening
  end

  # Pages (authenticated)
  scope "/api/v1/pages", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", PageController, :create
    patch "/:id", PageController, :update
    delete "/:id", PageController, :delete
    post "/:id/roles", PageController, :add_role
    delete "/:id/roles/:role_id", PageController, :remove_role
    patch "/:id/branding", PageController, :update_branding
  end

  # Pages (public / optional auth)
  scope "/api/v1/pages", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/", PageController, :index
    get "/:id", PageController, :show
    get "/:id/roles", PageController, :roles
    get "/:id/branding", PageController, :branding
  end

  # Conversations / Direct Messaging (authenticated)
  scope "/api/v1/conversations", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", ConversationController, :index
    post "/", ConversationController, :create
    get "/:id", ConversationController, :show
    post "/:id/messages", ConversationController, :send_message
    get "/:id/messages", ConversationController, :messages
    put "/:id/messages/:mid", ConversationController, :edit_message
    delete "/:id/messages/:mid", ConversationController, :delete_message
    post "/:id/read", ConversationController, :mark_read
    patch "/:id/settings", ConversationController, :update_settings
    post "/:id/accept", ConversationController, :accept
    delete "/:id/decline", ConversationController, :decline
    post "/:id/messages/:mid/reactions", ConversationController, :add_reaction
    delete "/:id/messages/:mid/reactions/:emoji", ConversationController, :remove_reaction
    get "/:id/messages/:mid/reactions", ConversationController, :message_reactions
  end

  # DM Preferences (authenticated)
  scope "/api/v1/dm_preferences", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", ConversationController, :dm_preferences
    patch "/", ConversationController, :update_dm_preferences
  end

  # SSE Streaming (authenticated)
  scope "/api/v1/streaming", HybridsocialWeb.Api.V1 do
    pipe_through [:sse, :authenticated]

    get "/user", StreamingController, :user
    get "/list/:id", StreamingController, :list
    get "/group/:id", StreamingController, :group
  end

  # SSE Streaming (optional auth)
  scope "/api/v1/streaming", HybridsocialWeb.Api.V1 do
    pipe_through [:sse, :optional_auth]

    get "/public", StreamingController, :public
    get "/hashtag/:tag", StreamingController, :hashtag
  end

  # Search (optional auth for visibility filtering)
  scope "/api/v1", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/search", SearchController, :index
  end

  # Ads (public serving)
  scope "/api/v1/ads", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/", AdController, :index
    post "/:id/click", AdController, :click
  end

  # Directory (public)
  scope "/api/v1/directory", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/new", DirectoryController, :new_users
  end

  # Trends (optional auth)
  scope "/api/v1/trends", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/tags", TrendController, :tags
    get "/statuses", TrendController, :statuses
    get "/links", TrendController, :links
  end

  # Funding (public)
  scope "/api/v1/instance", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/online", InstanceController, :online_count
    get "/funding", FundingController, :index
  end

  # Announcements (public + optional auth)
  scope "/api/v1/announcements", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/", AnnouncementController, :index
    post "/:id/dismiss", AnnouncementController, :dismiss
  end

  # Promotions (public)
  scope "/api/v1/promotions", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/pricing", PromotionController, :pricing
  end

  # Promotions (optional auth — promoted users for sidebar)
  scope "/api/v1/promotions", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/promoted", PromotionController, :promoted
  end

  # Promotions (authenticated)
  scope "/api/v1/promotions", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", PromotionController, :create
    get "/me", PromotionController, :status
    get "/history", PromotionController, :history
  end

  # Site Pages (public — privacy, terms, about)
  scope "/api/v1/pages/site", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/:slug", SitePageController, :show
  end

  # Custom Emojis (public)
  scope "/api/v1/custom_emojis", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/", CustomEmojiController, :index
  end

  # Scheduled statuses (authenticated)
  scope "/api/v1", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/statuses/schedule", ScheduledStatusController, :create
    get "/scheduled_statuses", ScheduledStatusController, :index
    put "/scheduled_statuses/:id", ScheduledStatusController, :update
    delete "/scheduled_statuses/:id", ScheduledStatusController, :delete
  end

  # Subscriptions (public plans)
  scope "/api/v1/subscriptions", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :rate_limited]

    get "/plans", SubscriptionController, :plans
  end

  # Subscriptions (authenticated)
  scope "/api/v1/subscriptions", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :rate_limited, :authenticated]

    post "/", SubscriptionController, :create
    get "/current", SubscriptionController, :current
    delete "/", SubscriptionController, :cancel
  end

  # Verification (authenticated)
  scope "/api/v1/verification", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :rate_limited, :authenticated]

    post "/apply", SubscriptionController, :apply_verification
    get "/status", SubscriptionController, :verification_status
    post "/vouch/:identity_id", SubscriptionController, :vouch_for_user
    get "/vouches/:identity_id", SubscriptionController, :get_vouches
  end

  # Data export / import (authenticated)
  scope "/api/v1", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :rate_limited, :authenticated]

    post "/export", ExportController, :create
    get "/export", ExportController, :index
    get "/export/:id", ExportController, :show
    get "/export/:id/download", ExportController, :download
    post "/import", ExportController, :import_data
  end

  # Reports (authenticated)
  scope "/api/v1/reports", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", ReportController, :create
  end

  # Appeals (authenticated — user-facing)
  scope "/api/v1/appeals", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", AppealController, :create
    get "/", AppealController, :index
  end

  # Admin routes (authenticated + admin)
  scope "/api/v1/admin", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :admin]

    # Dashboard
    get "/dashboard", AdminController, :dashboard

    # Instance Settings
    get "/settings", AdminController, :list_settings
    put "/settings", AdminController, :update_settings

    # Email
    get "/email", AdminController, :get_email_config
    put "/email", AdminController, :update_email_config
    post "/email/test", AdminController, :send_test_email

    # Theme
    get "/theme", AdminController, :get_theme
    put "/theme", AdminController, :update_theme
    post "/theme/logo", AdminController, :upload_logo
    post "/theme/favicon", AdminController, :upload_favicon

    # Instance Rules
    get "/rules", AdminController, :list_rules
    post "/rules", AdminController, :create_rule
    put "/rules/:index", AdminController, :update_rule
    delete "/rules/:index", AdminController, :delete_rule

    # Announcements
    get "/announcements", AdminController, :list_announcements
    post "/announcements", AdminController, :create_announcement
    put "/announcements/:id", AdminController, :update_announcement
    delete "/announcements/:id", AdminController, :delete_announcement

    # Reports
    get "/reports", AdminController, :list_reports
    get "/reports/:id", AdminController, :show_report
    post "/reports/:id/resolve", AdminController, :resolve_report
    post "/reports/:id/assign", AdminController, :assign_report

    # Audit Log
    get "/audit_log", AdminController, :audit_log

    # Accounts (aliased as /users for frontend compatibility)
    get "/accounts", AdminController, :list_accounts
    get "/users", AdminController, :list_accounts
    get "/users/:id", AdminController, :show_account
    post "/accounts/:id/action", AdminController, :account_action
    post "/users/:id/suspend", AdminController, :suspend_account
    post "/users/:id/unsuspend", AdminController, :unsuspend_account
    post "/users/:id/warn", AdminController, :warn_account
    post "/users/:id/silence", AdminController, :silence_account
    post "/users/:id/unsilence", AdminController, :unsilence_account
    post "/users/:id/shadow_ban", AdminController, :shadow_ban_account
    post "/users/:id/unshadow_ban", AdminController, :unshadow_ban_account
    post "/users/:id/force_sensitive", AdminController, :force_sensitive_account
    post "/users/:id/unforce_sensitive", AdminController, :unforce_sensitive_account
    post "/users/:id/revoke_sessions", AdminController, :revoke_sessions
    post "/users/:id/trust_level", AdminController, :set_trust_level

    # Ads management
    get "/ads", AdminController, :list_ads
    post "/ads", AdminController, :create_ad
    put "/ads/:id", AdminController, :update_ad
    delete "/ads/:id", AdminController, :delete_ad
    post "/ads/:id/toggle", AdminController, :toggle_ad
    get "/users/:id/notes", AdminController, :list_notes
    post "/users/:id/notes", AdminController, :create_note

    # Analytics
    get "/analytics/summary", AdminController, :analytics_summary
    get "/analytics/user_growth", AdminController, :analytics_user_growth
    get "/analytics/post_volume", AdminController, :analytics_post_volume
    get "/analytics/active_users", AdminController, :analytics_active_users
    get "/analytics/reactions", AdminController, :analytics_reactions
    get "/analytics/follows", AdminController, :analytics_follows

    # Job queue
    get "/queue_stats", AdminController, :queue_stats

    # Promotions management
    get "/promotions", AdminController, :list_promotions
    post "/promotions", AdminController, :admin_create_promotion
    post "/promotions/:id/cancel", AdminController, :cancel_promotion

    # Approval queue
    get "/pending_accounts", AdminController, :pending_accounts
    post "/pending_accounts/:id/approve", AdminController, :approve_account
    post "/pending_accounts/:id/reject", AdminController, :reject_account

    # Suggested users curation
    post "/users/:id/suggest", AdminController, :suggest_user
    post "/users/:id/unsuggest", AdminController, :unsuggest_user

    # Name revocation
    post "/users/:id/revoke_name", AdminController, :revoke_name
    post "/users/:id/bot_rate_limit", AdminController, :set_bot_rate_limit
    post "/users/:id/force_bot", AdminController, :force_bot
    post "/users/:id/unforce_bot", AdminController, :unforce_bot

    # Admin user management
    put "/users/:id/profile", AdminController, :edit_user_profile
    post "/users/:id/reset_password", AdminController, :reset_user_password
    get "/users/:id/email", AdminController, :view_user_email
    put "/users/:id/email", AdminController, :change_user_email
    put "/users/:id/tier", AdminController, :change_user_tier
    post "/users/:id/set_admin", AdminController, :set_admin
    post "/users/:id/assign_role", AdminController, :assign_user_role
    post "/users/:id/remove_role", AdminController, :remove_user_role

    # Content Filters
    get "/content_filters", AdminController, :list_filters
    post "/content_filters", AdminController, :create_filter
    delete "/content_filters/:id", AdminController, :delete_filter

    # Banned Domains
    get "/banned_domains", AdminController, :list_banned_domains
    post "/banned_domains", AdminController, :ban_domain
    delete "/banned_domains/:domain", AdminController, :unban_domain

    # Relays
    get "/relays", AdminController, :list_relays
    post "/relays", AdminController, :subscribe_relay
    delete "/relays/:id", AdminController, :unsubscribe_relay

    # Backups
    post "/backup", Admin.BackupController, :create
    get "/backups", Admin.BackupController, :index
    get "/backups/:id", Admin.BackupController, :show

    # Roles & Permissions
    get "/roles", Admin.RolesController, :index
    post "/roles", Admin.RolesController, :create
    patch "/roles/:id", Admin.RolesController, :update
    delete "/roles/:id", Admin.RolesController, :delete
    get "/roles/:id/permissions", Admin.RolesController, :permissions
    post "/roles/:id/permissions", Admin.RolesController, :add_permission
    delete "/roles/:id/permissions/:pid", Admin.RolesController, :remove_permission
    get "/permissions", Admin.RolesController, :list_all_permissions

    # User role assignment
    post "/users/:user_id/roles", Admin.RolesController, :assign_role
    delete "/users/:user_id/roles/:role_id", Admin.RolesController, :revoke_role

    # Verifications
    get "/verifications", AdminController, :list_verifications
    post "/verifications/:id/approve", AdminController, :approve_verification
    post "/verifications/:id/reject", AdminController, :reject_verification

    # Instance Policies
    get "/known_instances", AdminController, :list_known_instances
    get "/instance_policies", AdminController, :list_instance_policies
    post "/instance_policies", AdminController, :create_instance_policy
    put "/instance_policies/:id", AdminController, :update_instance_policy
    delete "/instance_policies/:id", AdminController, :delete_instance_policy
    post "/instance_policies/:id/purge", AdminController, :purge_instance_content
    post "/instance_policies/:id/purge_preview", AdminController, :purge_instance_preview

    # Webhooks
    get "/webhooks", AdminController, :list_webhooks
    post "/webhooks", AdminController, :create_webhook
    put "/webhooks/:id", AdminController, :update_webhook
    delete "/webhooks/:id", AdminController, :delete_webhook

    # IP Bans
    get "/ip_bans", AdminController, :list_ip_bans
    post "/ip_bans", AdminController, :create_ip_ban
    delete "/ip_bans/:id", AdminController, :delete_ip_ban

    # Email Domain Bans
    get "/email_domain_bans", AdminController, :list_email_domain_bans
    post "/email_domain_bans", AdminController, :create_email_domain_ban
    delete "/email_domain_bans/:id", AdminController, :delete_email_domain_ban

    # Media Hash Bans
    get "/media_hash_bans", AdminController, :list_media_hash_bans
    post "/media_hash_bans", AdminController, :create_media_hash_ban
    post "/media_hash_bans/from_post/:post_id", AdminController, :create_media_hash_ban_from_post
    delete "/media_hash_bans/:id", AdminController, :delete_media_hash_ban

    # Appeals
    get "/appeals", AdminController, :list_appeals
    post "/appeals/:id/approve", AdminController, :approve_appeal
    post "/appeals/:id/reject", AdminController, :reject_appeal

    # Moderation Notes
    get "/accounts/:id/notes", AdminController, :list_moderation_notes
    post "/accounts/:id/notes", AdminController, :create_moderation_note
    delete "/notes/:id", AdminController, :delete_moderation_note

    # Invite Codes
    get "/invites", AdminController, :list_invites
    post "/invites", AdminController, :create_invite
    delete "/invites/:id", AdminController, :delete_invite

    # Trust Levels
    post "/accounts/:id/trust_level", AdminController, :set_trust_level

    # Admin Post Management
    get "/posts/:id", AdminController, :show_post
    delete "/posts/:id", AdminController, :delete_post
    post "/posts/:id/sensitive", AdminController, :force_sensitive
    post "/posts/:id/unsensitive", AdminController, :remove_sensitive

    # Moderation Queue
    get "/moderation_queue", AdminController, :list_moderation_queue
    get "/moderation_queue/stats", AdminController, :moderation_queue_stats
    post "/moderation_queue/:id/approve", AdminController, :approve_queued_item
    post "/moderation_queue/:id/reject", AdminController, :reject_queued_item
    post "/moderation_queue/:id/escalate", AdminController, :escalate_queued_item

    # Site Pages (legal / about)
    get "/site_pages", Admin.SitePagesController, :index
    get "/site_pages/:id", Admin.SitePagesController, :show
    put "/site_pages/:id", Admin.SitePagesController, :update
    post "/site_pages/seed", Admin.SitePagesController, :seed
  end

  # Markers (authenticated)
  scope "/api/v1/markers", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    get "/", MarkerController, :index
    post "/", MarkerController, :create
  end

  # Media proxy (public)
  scope "/proxy", HybridsocialWeb do
    pipe_through :api

    get "/media/:signature/:encoded_url", MediaProxyController, :show
  end

  # --- Federation / ActivityPub ---

  scope "/.well-known", HybridsocialWeb.Federation do
    pipe_through :api

    get "/webfinger", WebfingerController, :show
    get "/nodeinfo", NodeinfoController, :well_known
  end

  # Instance info (public)
  scope "/api/v1", HybridsocialWeb.Api.V1 do
    pipe_through :api

    get "/instance", InstanceController, :show
  end

  # NodeInfo
  scope "/nodeinfo", HybridsocialWeb.Federation do
    pipe_through :api

    get "/2.0", NodeinfoController, :show
  end

  # Instance actor (public)
  scope "/", HybridsocialWeb.Federation do
    pipe_through :api

    get "/actor", InstanceActorController, :show
  end

  scope "/actors", HybridsocialWeb.Federation do
    pipe_through :api

    get "/:id", ActorController, :show
    get "/:id/followers", ActorController, :followers
    get "/:id/following", ActorController, :following
    get "/:id/collections/featured", ActorController, :featured
    get "/:id/outbox", ActorController, :outbox
    post "/:id/inbox", InboxController, :actor_inbox
  end

  scope "/", HybridsocialWeb.Federation do
    pipe_through :api

    post "/inbox", InboxController, :shared_inbox
  end
end
