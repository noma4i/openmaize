if Code.ensure_loaded?(Ecto) do

  defmodule Openmaize.DB do
    @moduledoc """
    Functions to help with interacting with Ecto when using Openmaize.

    ## Creating a custom database module

    This is the default database module, but you can use a custom module
    by changing the `db_module` value in the config file.

    If you are going to create a custom module, note that the following
    functions are called by other modules in Openmaize:

    * `find_user` - used in Openmaize.Login and Openmaize.Confirm
    * `user_confirmed` - used in Openmaize.Confirm
    * `password_reset` - used in Openmaize.Confirm
    * `check_time` - used in Openmaize.Confirm

    ## User model

    The example schema below is the most basic setup for Openmaize
    (:username and :password_hash are configurable):

        schema "users" do
          field :username, :string
          field :role, :string
          field :password, :string, virtual: true
          field :password_hash, :string

          timestamps
        end

    In the example above, the `:username` is used to identify the user. This can
    be set to any other value, such as `:email`. See the documentation for
    Openmaize.Login for details about logging in with a different value.

    See the documentation for Openmaize.Config for details about configuring
    the `:password_hash` value.

    The `:role` is needed for authorization, and the `:password` and the
    `:password_hash` fields are needed for the `add_password_hash` function
    in this module (see the documentation for Openmaize.Config for information
    about changing :password_hash to some other value). Note the addition
    of `virtual: true` to the definition of the password field. This means
    that it will not be stored in the database.

    """

    import Ecto.{Changeset, Query}
    alias Openmaize.{Config, Password}

    @doc """
    Find the user in the database.
    """
    def find_user(user_id, uniq) do
      from(u in Config.user_model,
          where: field(u, ^uniq) == ^user_id,
          select: u)
      |> Config.repo.one
    end

    @doc """
    Hash the password and add it to the user model or changeset.

    This function will return a changeset. If there are any errors, they
    will be added to the changeset.

    Comeonin.Bcrypt is the default hashing function, but this can be changed to
    Comeonin.Pbkdf2 by setting the Config.get_crypto_mod value to :pbkdf2.

    ## Options

    If you do not have NotQwerty123 installed, there is one option:

    * min_length - the minimum length of the password

    If you have NotQwerty123 installed, there are three options:

    * min_length - the minimum length of the password
    * extra_chars - check for punctuation characters (including spaces) and digits
    * common - check to see if the password is too common (too easy to guess)

    See the documentation for Openmaize.Password for more information.

    ## Examples

        Openmaize.DB.add_password_hash(user, params, [min_length: 12])

    This command will check that the password is at least 12 characters long
    before hashing it and adding the hash to the user changeset.
    """
    def add_password_hash(user, params, opts \\ []) do
      (params[:password] || params["password"])
      |> Password.valid_password?(opts)
      |> add_hash_changeset(user)
    end

    @doc """
    Add a confirmation token to the user model or changeset.

    Add the following three entries to your user schema:

        field :confirmation_token, :string
        field :confirmation_sent_at, Ecto.DateTime
        field :confirmed_at, Ecto.DateTime

    ## Examples

    In the following example, the `add_confirm_token` function is called with
    a key generated by `gen_token_link`:

        changeset
        |> Openmaize.DB.add_confirm_token(key)

    """
    def add_confirm_token(user, key) do
      change(user, %{confirmation_token: key, confirmation_sent_at: Ecto.DateTime.utc})
    end

    @doc """
    Add a reset token to the user model and update the database.

    Add the following two entries to your user schema:

    field :reset_token, :string
    field :reset_sent_at, Ecto.DateTime

    As with `add_confirm_token`, the function `gen_token_link` can be used
    to generate the token and link.
    """
    def add_reset_token(user, key) do
      change(user, %{reset_token: key, reset_sent_at: Ecto.DateTime.utc})
      |> Config.repo.update
    end

    @doc """
    Change the `confirmed_at` value in the database to the current time.
    """
    def user_confirmed(user) do
      change(user, %{confirmed_at: Ecto.DateTime.utc}) |> Config.repo.update
    end

    @doc """
    Add the password hash for the new password to the database.

    If the update is successful, the reset_token and reset_sent_at
    values will be set to nil.

    This function is used by the Openmaize.Confirm module.
    """
    def password_reset(user, password) do
      Config.repo.transaction(fn ->
        user = change(user, %{Config.hash_name => Config.get_crypto_mod.hashpwsalt(password)})
        |> Config.repo.update!

        change(user, %{reset_token: nil, reset_sent_at: nil})
        |> Config.repo.update!
      end)
    end

    @doc """
    Function used to check if a token has expired.

    This function is used by the Openmaize.Confirm module.
    """
    def check_time(nil, _), do: false
    def check_time(sent_at, valid_secs) do
      (sent_at |> Ecto.DateTime.to_erl
       |> :calendar.datetime_to_gregorian_seconds) + valid_secs >
      (:calendar.universal_time |> :calendar.datetime_to_gregorian_seconds)
    end

    @doc """
    Generate a confirmation token and a link containing the email address
    and the token.

    The link is used to create the url that the user needs to follow to
    confirm the email address.

    The user_id is the actual name or email address of the user, and
    unique_id refers to the type of identifier. For example, if you
    want to use `username=fred` in your link, you need to set the
    unique_id to :username. The default unique_id is :email.
    """
    def gen_token_link(user_id, unique_id \\ :email) do
      key = :crypto.strong_rand_bytes(24) |> Base.url_encode64
      {key, "#{unique_id}=#{URI.encode_www_form(user_id)}&key=#{key}"}
    end

    defp add_hash_changeset({:ok, password}, user) do
      change(user, %{Config.hash_name => Config.get_crypto_mod.hashpwsalt(password)})
    end
    defp add_hash_changeset({:error, message}, user) do
      change(user, %{password: ""}) |> add_error(:password, message)
    end
  end

end
