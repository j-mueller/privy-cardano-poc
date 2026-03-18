{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Servant API for privy-compatible transaction builder
module Privy.API (
    API,
    APIInEra,
) where

import Cardano.Api qualified as C
import Privy.API.Wallet qualified as Wallet
import Privy.Orphans ()
import Servant.API (
    Description,
    Get,
    JSON,
    NoContent,
    (:<|>),
    type (:>),
 )

type API era =
    "healthcheck" :> Description "Is the server alive?" :> Get '[JSON] NoContent
        :<|> Wallet.API era

type APIInEra = "api" :> "v1" :> API C.ConwayEra
