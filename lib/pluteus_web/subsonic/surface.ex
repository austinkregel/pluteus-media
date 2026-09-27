defmodule PluteusWeb.Subsonic.Surface do
  @moduledoc """
  One group of OpenSubsonic endpoints: which they are, what each needs granted,
  and how to answer one.

  The three were already a convention across `Browse`, `Lists`, `Retrieval` and
  `Own`; naming them makes a surface that omits `operations/1` a compile warning
  rather than a request that reaches the endpoint unclassified.

  `operations/1` is spec-06 §4.2's classification: what a credential must have
  been granted for this endpoint to be answered. It is a clause per endpoint group
  with no catch-all, so **an endpoint nobody classified raises** rather than
  defaulting to permitted. A grant is checked on every request (spec-07 §3.4), and
  the check is in `PluteusWeb.SubsonicController.dispatch/2`, which every
  key-authenticated request passes through.

  The classification lives beside each surface's `endpoints/0` rather than in one
  table, because a second list of the same endpoints is a second thing to keep in
  step and it would drift.
  """

  @doc """
  Every endpoint this surface answers.
  """
  @callback endpoints() :: [String.t()]

  @doc """
  Every operation a credential must hold to reach one of them.

  Conjunctive: the credential must hold all of them. An endpoint is classified by
  the widest operation it may perform rather than by what a particular set of
  parameters would perform, so a credential is refused rather than being let
  through on the narrow reading of a call that could go either way. Erring toward
  refusal is the direction §4.2 asks for.
  """
  @callback operations(String.t()) :: [atom()]

  @doc """
  Answers one of them.
  """
  @callback handle(String.t(), Plug.Conn.t()) :: Plug.Conn.t()
end
