module Privy.API.Tx (
    ApiTx,
) where

import Cardano.Api qualified as C
import Privy.API.TextEnvelope (TextEnvelopeJSON)

type ApiTx era = TextEnvelopeJSON (C.Tx era)
