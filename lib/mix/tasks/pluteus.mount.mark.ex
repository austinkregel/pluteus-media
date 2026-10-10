defmodule Mix.Tasks.Pluteus.Mount.Mark do
  @shortdoc "Marks this environment's roots as mounted"

  @moduledoc """
  Writes `.pluteus/mount-check` under primary storage and the inbox.

  For the roots a development tree and a test run own outright, which are ordinary
  directories rather than volumes and so have nobody to place the file for them.

  A mounted volume's sentinel is placed by hand. This task is Mix's, so a release does
  not carry it: a deployment able to write its own evidence of a mount would be
  answering the question by asking itself.
  """

  use Mix.Task

  alias Pluteus.Storage.Mount

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    Mount.mark!()

    for {name, root} <- Mount.roots() do
      Mix.shell().info("marked #{name} at #{root}")
    end

    :ok
  end
end
