defmodule HybridsocialWeb.UserSocket do
  use Phoenix.Socket

  channel "direct:*", HybridsocialWeb.DirectChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Hybridsocial.Auth.Token.verify_access_token(token) do
      {:ok, claims} ->
        {:ok, assign(socket, :identity_id, claims["sub"])}

      _error ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.identity_id}"
end
