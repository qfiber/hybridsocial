defmodule HybridsocialWeb.Router do
  use HybridsocialWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
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
  end

  # Authenticated auth endpoints
  scope "/api/v1/auth", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/logout", AuthController, :logout
    get "/me", AuthController, :me
    post "/2fa/setup", AuthController, :setup_2fa
    post "/2fa/verify", AuthController, :verify_2fa
    delete "/2fa", AuthController, :disable_2fa
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

    # Actor migration
    post "/migrate", AccountController, :migrate
    post "/also_known_as", AccountController, :also_known_as
  end

  # Public account endpoints (optional auth for visibility filtering)
  scope "/api/v1/accounts", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/lookup", AccountController, :lookup
    get "/:id/followers", AccountController, :followers
    get "/:id/following", AccountController, :following
    get "/:id/statuses", AccountController, :statuses
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

    post "/:id/react", StatusController, :react
    delete "/:id/react", StatusController, :unreact

    post "/:id/boost", StatusController, :boost
    delete "/:id/boost", StatusController, :unboost

    post "/:id/pin", StatusController, :pin
    delete "/:id/pin", StatusController, :unpin

    post "/:id/view", StatusController, :view

    post "/:id/bookmark", BookmarkController, :create
    delete "/:id/bookmark", BookmarkController, :delete
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

    get "/funding", FundingController, :index
  end

  # Announcements (public + optional auth)
  scope "/api/v1/announcements", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :optional_auth]

    get "/", AnnouncementController, :index
    post "/:id/dismiss", AnnouncementController, :dismiss
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
  end

  # Data export / import (authenticated)
  scope "/api/v1", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :rate_limited, :authenticated]

    post "/export", ExportController, :create
    get "/export", ExportController, :index
    get "/export/:id", ExportController, :show
    post "/import", ExportController, :import_data
  end

  # Reports (authenticated)
  scope "/api/v1/reports", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :authenticated]

    post "/", ReportController, :create
  end

  # Admin routes (authenticated + admin)
  scope "/api/v1/admin", HybridsocialWeb.Api.V1 do
    pipe_through [:api, :admin]

    # Reports
    get "/reports", AdminController, :list_reports
    get "/reports/:id", AdminController, :show_report
    post "/reports/:id/resolve", AdminController, :resolve_report
    post "/reports/:id/assign", AdminController, :assign_report

    # Audit Log
    get "/audit_log", AdminController, :audit_log

    # Accounts
    get "/accounts", AdminController, :list_accounts
    post "/accounts/:id/action", AdminController, :account_action

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
