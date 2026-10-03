defmodule Pluteus.Repo.Migrations.ReadAContainersOwnDocument do
  use Ecto.Migration

  # spec-04 §6.9 criterion 35. A metadata document the registry names inside a container is
  # read at identification as an embedded tag. Identification runs before placement and
  # the two stages are separate, so what the document stated is carried on the acquisition
  # alongside the probe that answers the same question for a container with streams.
  #
  # The column holds what a document inside the container stated, and no document was read
  # for any acquisition identified before it existed. The empty default is therefore what
  # those acquisitions hold rather than a value standing in for one that is missing.
  def change do
    alter table(:acquisitions) do
      add :container_tags, :map, null: false, default: "{}"
    end
  end
end
