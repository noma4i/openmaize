defmodule Openmaize.OnetimePass.Base do
  @moduledoc """
  Module to handle one-time passwords for use in two factor authentication.
  """

  import Plug.Conn
  alias Comeonin.Otp

  @doc """
  Check the one-time password, HOTP or TOTP.
  """
  def check_key(user, %{"hotp" => hotp}, opts) do
    {user, Otp.check_hotp(hotp, user.otp_secret, opts)}
  end
  def check_key(user, %{"totp" => totp}, opts) do
    {user, Otp.check_totp(totp, user.otp_secret, opts)}
  end

  @doc """
  Handle the failure / success of the login and return the `conn`.
  """
  def handle_auth({_, false}, conn) do
    put_private(conn, :openmaize_error, "Invalid credentials")
  end
  def handle_auth({user, last}, conn) do
    put_private(conn, :openmaize_user, Map.put(user, last: last))
  end
end
