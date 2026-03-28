module Privy.Env.Operator (
    OperatorEnv (..),
) where

import Cardano.Api qualified as C

data OperatorEnv era
    = OperatorEnv
    { bteOperator :: (C.Hash C.PaymentKey, C.StakeAddressReference)
    , bteOperatorUtxos :: C.UTxO era
    }
