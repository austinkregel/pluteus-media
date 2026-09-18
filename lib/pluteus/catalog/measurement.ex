defmodule Pluteus.Catalog.Measurement do
  @moduledoc """
  What was read from the bytes at one location: their size, digest and
  identified format (spec-03 §5.1, §6).

  Only `Pluteus.Catalog.measure/1` builds one. Reading a large file takes as
  long as the file is large, so a caller that is about to open a transaction
  measures first and hands the measurement in, rather than holding the
  transaction open while the bytes are read.
  """

  @enforce_keys [:location, :size, :digest, :digest_algorithm, :format]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          location: String.t(),
          size: non_neg_integer(),
          digest: String.t(),
          digest_algorithm: String.t(),
          format: String.t()
        }
end
