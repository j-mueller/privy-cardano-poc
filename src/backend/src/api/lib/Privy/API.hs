{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Servant API for privy-compatible transaction builder
module Privy.API (
    API,
    APIInEra,
    APIWithStatic,
    APIWithStaticInEra,
) where

import Cardano.Api qualified as C
import Privy.API.NetworkId qualified as NetworkId
import Privy.API.RawSign qualified as RawSign
import Privy.API.SendFunds qualified as SendFunds
import Privy.API.Steps qualified as Steps
import Privy.API.SubmitTx qualified as SubmitTx
import Privy.API.Wallet qualified as Wallet
import Privy.Orphans ()
import Servant.API (
    Description,
    Get,
    JSON,
    NoContent,
    Raw,
    (:<|>),
    type (:>),
 )

type API era =
    "healthcheck" :> Description "Is the server alive?" :> Get '[JSON] NoContent
        :<|> NetworkId.API era
        :<|> RawSign.API
        :<|> SendFunds.API era
        :<|> Steps.BuildTxAPI era
        :<|> Wallet.API era
        :<|> SubmitTx.API era

type APIInEra = "api" :> "v1" :> API C.ConwayEra

type APIWithStatic era = ("api" :> "v1" :> API era) :<|> Raw

type APIWithStaticInEra = APIWithStatic C.ConwayEra
