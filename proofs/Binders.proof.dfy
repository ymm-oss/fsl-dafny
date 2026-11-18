// SPDX-License-Identifier: Apache-2.0

include "../out/Binders.gen.dfy"

module BindersProof refines BindersSpec {
  lemma InitEstablishes(c: Config)
  {
  }

  lemma raise_Preserves(c: Config, st: State, n: int)
  {
  }

  lemma lower_Preserves(c: Config, st: State, n: int)
  {
  }
}
