defmodule HiveforgeController.Common do
  def hash_key(nil), do: nil

  def hash_key(key) do
    Argon2.hash_pwd_salt(key,
      t_cost: 3,
      m_cost: 65536,
      parallelism: 4
    )
  end

  def verify_key(key, hash) do
    Argon2.verify_pass(key, hash)
  end
end
