defmodule Mirror.Engine.Rng do
  @moduledoc """
  Deterministic RNG state for engine operations.
  """

  @type t :: %__MODULE__{seed: non_neg_integer()}
  defstruct seed: 0

  @modulus 2_147_483_648
  @multiplier 1_103_515_245
  @increment 12_345

  @spec new(integer()) :: t()
  def new(seed) when is_integer(seed) do
    %__MODULE__{seed: Integer.mod(seed, @modulus)}
  end

  @spec next(t()) :: {non_neg_integer(), t()}
  def next(%__MODULE__{} = rng) do
    seed = Integer.mod(rng.seed * @multiplier + @increment, @modulus)
    {seed, %{rng | seed: seed}}
  end

  @spec uniform(t(), pos_integer()) :: {non_neg_integer(), t()}
  def uniform(%__MODULE__{} = rng, n) when is_integer(n) and n > 0 do
    {value, rng} = next(rng)
    {Integer.mod(value, n), rng}
  end
end
