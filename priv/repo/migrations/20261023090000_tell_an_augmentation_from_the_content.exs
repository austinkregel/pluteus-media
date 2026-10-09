defmodule Pluteus.Repo.Migrations.TellAnAugmentationFromTheContent do
  @moduledoc """
  spec-01 §5.3 names three kinds of aggregate — collections, augmentations and parallel
  expressions — and the record cannot tell the third from the second. A commentary is an
  expression of a work of its own embodied in the film's manifestation (spec-04 §6.5),
  and a dub is a parallel expression of the film itself: both are a row in `embodiments`
  and nothing says which.

  The difference matters to anything asking what the household holds. An augmenting
  expression's work has no manifestation of its own, so it is a track of someone else's
  holding rather than a holding, and a surface that cannot tell them apart lists the
  commentary beside the film.

  Every existing row is content. `create_work_embodied_in/2` is the only thing that has
  ever made an augmentation, and no manifestation in this deployment carries expressions
  of more than one work, so `false` states what is true of each row rather than standing
  in for something unrecorded.
  """

  use Ecto.Migration

  def change do
    alter table(:embodiments) do
      add :augmentation, :boolean, null: false, default: false
    end
  end
end
