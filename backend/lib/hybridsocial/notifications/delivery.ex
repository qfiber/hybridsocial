defmodule Hybridsocial.Notifications.Delivery do
  @moduledoc "Behaviour for notification delivery channels."

  @type notification_payload :: %{
          title: String.t(),
          body: String.t(),
          tag: String.t(),
          data: map()
        }

  @callback deliver(recipient_id :: String.t(), payload :: notification_payload(), opts :: map()) ::
              :ok | {:error, term()}
  @callback channel_name() :: atom()
  @callback available?() :: boolean()
end
