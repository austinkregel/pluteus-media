defmodule Pluteus.Analysis.Tool do
  @moduledoc """
  The contract every analysing tool meets, wherever it runs (spec-04 §8.3).

  A tool describes itself without analysing anything, analyses one input per
  request and holds no queue of its own, returns measurements by name as it
  computed them, and writes nothing anywhere.

  A request names bytes and, where the input is one stream or one extent of a
  file, which stream and which span. It never names a catalog entity: the tool
  has no catalog to look one up in.
  """

  @type description :: %{name: String.t(), version: String.t(), schema_version: pos_integer()}

  @type request :: %{
          path: Path.t(),
          stream_index: non_neg_integer() | nil,
          start_ms: non_neg_integer() | nil,
          end_ms: non_neg_integer() | nil
        }

  @type failure :: {:error, :transient | :permanent, term()}

  @callback describe() :: {:ok, description()} | failure()
  @callback analyse(request()) :: {:ok, map()} | failure()
end
