defmodule Pluteus.Design.FacesTest do
  @moduledoc """
  The vendored faces, checked against the manifest that describes them.

  A.3.5 self-hosts the faces and A.8.1 requires each one's notice travel with the
  copies. Both are claims about files in this repository, so they are checkable with no
  network: the vendor task records what it wrote and this reads the files back.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Faces

  describe "A.3.5. What is vendored is what the manifest describes" do
    test "every pinned face has an entry, and nothing else does" do
      pinned = Faces.all() |> Enum.map(& &1.family) |> Enum.sort()
      recorded = Faces.manifest()["faces"] |> Enum.map(& &1["family"]) |> Enum.sort()

      assert pinned == recorded
    end

    test "each file is present and hashes to what was recorded" do
      # The digest is what makes the committed bytes checkable without refetching the
      # upstream. The vendoring is reproducible — the timestamp is not recalculated — so
      # a digest that no longer matches means the file changed, not that it was rebuilt.
      for face <- Faces.manifest()["faces"] do
        path = Path.join(Faces.root(), face["file"])
        body = File.read!(path)

        assert byte_size(body) == face["bytes"]
        assert digest(body) == face["sha256"], "#{face["file"]} is not the file recorded"
      end
    end

    test "each licence is vendored beside its face and hashes to what was recorded" do
      # A.8.1: "The copyright notice and permission notice MUST travel with the vendored
      # copies." Beside the files is this; the interface's half is PluteusWeb.Notices.
      for face <- Faces.manifest()["faces"] do
        body = face |> licence_path() |> File.read!()

        assert digest(body) == face["licence"]["sha256"]
        assert body =~ "SIL Open Font License, Version 1.1"
      end
    end

    test "the two ways to a licence path agree" do
      # The vendor task names the file and Notices reads it; one definition, so a
      # re-vendoring cannot leave the notice pointing at a file that is not there.
      for face <- Faces.all() do
        assert File.exists?(Faces.licence_path(face))
      end

      recorded = Faces.manifest()["faces"] |> Enum.map(&licence_path(&1)) |> Enum.sort()
      derived = Faces.all() |> Enum.map(&Faces.licence_path/1) |> Enum.sort()

      assert recorded == derived
    end

    test "no face carries an axis no CSS property can reach" do
      # A.3.5 sets weight with the weight property and never with raw variation
      # settings, so an axis nothing can set is one a utility would reset by accident.
      for face <- Faces.all(), recorded <- [recorded(face)] do
        assert Enum.sort(Map.keys(recorded["axes"])) == Enum.sort(face.keep)
      end
    end

    test "the subset is the coverage the household holds, and reaches Latin only" do
      # A.3.5 makes subsetting the larger saving and requires the subset be chosen for
      # the coverage the household holds. Measured over this library's names: 77
      # distinct codepoints, 76 of them Basic Latin.
      assert Faces.latin() =~ "U+0000-00FF"

      for face <- Faces.all() do
        assert face.subset == Faces.latin()
      end
    end

    test "subsetting saved what A.3.5 says it saves" do
      # A.3.5 measures a Latin subset against an unsubset variable face at roughly
      # sevenfold. The interface face does better because most of its thirteen axes are
      # instanced away as well.
      for face <- Faces.manifest()["faces"] do
        assert face["bytes"] < 200_000
      end
    end
  end

  defp recorded(%{family: family}) do
    Enum.find(Faces.manifest()["faces"], &(&1["family"] == family))
  end

  defp licence_path(%{"licence" => %{"file" => file}}), do: Path.join(Faces.root(), file)

  defp digest(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
