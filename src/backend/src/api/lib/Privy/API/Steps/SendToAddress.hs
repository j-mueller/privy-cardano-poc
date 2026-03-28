{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

module Privy.API.Steps.SendToAddress (
    SendToAddressStep (..),
    buildSendToAddressStep,
) where

import Cardano.Api qualified as C
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Generics (Generic)
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.SerialisedPlutusDatum (SerialisedPlutusDatum)
import Privy.API.Steps.StepResult (StepResult (..))
import Privy.API.Utils (jsonOptions)

data SendToAddressStep
    = SendToAddressStep
    { stasDestination :: SerialiseAddress (C.Address C.ShelleyAddr)
    , stasInlineDatum :: Maybe SerialisedPlutusDatum
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON SendToAddressStep where
    toJSON = Aeson.genericToJSON (jsonOptions 4)
    toEncoding = Aeson.genericToEncoding (jsonOptions 4)

instance FromJSON SendToAddressStep where
    parseJSON = Aeson.genericParseJSON (jsonOptions 4)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''SendToAddressStep)

instance Schema.ToSchema SendToAddressStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 4))

buildSendToAddressStep ::
    SendToAddressStep ->
    StepResult SerialisedPlutusDatum
buildSendToAddressStep SendToAddressStep{stasDestination, stasInlineDatum} =
    StepResult
        { srDatum = stasInlineDatum
        , srAddress = unSerialiseAddress stasDestination
        , srValue = mempty
        }
