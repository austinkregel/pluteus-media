defmodule Pluteus.AnalysisTools do
  @moduledoc """
  Deriving tools that behave as a test needs: a second well-behaved tool, and
  tools that break the contract in each way spec-04 §8.3 and §9 name.
  """

  defmodule Second do
    @moduledoc "A well-behaved tool whose version the test process chooses."
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe,
      do:
        {:ok,
         %{
           name: "second-tool",
           version: Process.get(:second_tool_version, "1"),
           schema_version: 1
         }}

    @impl true
    def analyse(request) do
      {:ok,
       %{"schema_version" => 1, "measurements" => %{"duration_hint" => byte_size(request.path)}}}
    end
  end

  defmodule Undefined do
    @moduledoc """
    Answers as the native analyser does for a signal it cannot measure: a
    well-formed response whose measurements omit the one the field registry
    names, because the level of silence and the loudness of a signal entirely
    below the absolute gate are undefined rather than zero.
    """
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe,
      do: {:ok, %{name: "pluteus-native", version: "undefined-case", schema_version: 1}}

    @impl true
    def analyse(_request),
      do: {:ok, %{"schema_version" => 1, "measurements" => %{"spectral_centroid" => 0.0}}}
  end

  defmodule Positional do
    @moduledoc "Returns a vector whose meaning is its order."
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe, do: {:ok, %{name: "positional-tool", version: "1", schema_version: 1}}

    @impl true
    def analyse(_request),
      do: {:ok, %{"schema_version" => 1, "measurements" => %{"mfcc" => [1.0, 2.0, 3.0]}}}
  end

  defmodule UnknownSchema do
    @moduledoc "Speaks a wire schema the deployment has never seen."
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe, do: {:ok, %{name: "future-tool", version: "1", schema_version: 99}}

    @impl true
    def analyse(_request), do: {:ok, %{"schema_version" => 99, "measurements" => %{"x" => 1}}}
  end

  defmodule Undecodable do
    @moduledoc "Fails the same way on every attempt."
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe,
      do:
        {:ok,
         %{
           name: "strict-tool",
           version: Process.get(:strict_tool_version, "1"),
           schema_version: 1
         }}

    @impl true
    def analyse(_request), do: {:error, :permanent, :undecodable_bytes}
  end

  defmodule Raising do
    @moduledoc "Raises instead of answering."
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe, do: {:ok, %{name: "raising-tool", version: "1", schema_version: 1}}

    @impl true
    def analyse(_request), do: raise("the tool fell over")
  end

  defmodule Unavailable do
    @moduledoc "Answers its description and then times out on every analysis."
    @behaviour Pluteus.Analysis.Tool

    @impl true
    def describe, do: {:ok, %{name: "flaky-tool", version: "1", schema_version: 1}}

    @impl true
    def analyse(_request), do: {:error, :transient, :timeout}
  end
end
