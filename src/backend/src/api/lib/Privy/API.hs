{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Servant API for privy-compatible transaction builder
module Privy.API(
  API,
  APIInEra
) where

import Cardano.Api qualified as C
import Privy.API.Types (PrivyPublicKey)

type API era =
  "healthcheck" :> Description "Is the server alive?" :> Get '[JSON] NoContent
    :<|> "wallet" :> Capture "public_key" PrivyPublicKey :> Get '[JSON] (SerialiseAddress (C.Address C.ShelleyAddr))
    

type APIInEra = "api" :> "v1" :> API C.ConwayEra
