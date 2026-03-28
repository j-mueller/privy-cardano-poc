{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Steps (
    TxFlowStep (..),
    MinSwapStep (..),
    PulseStep (..),
    MuesliSwapStep (..),
    SendToAddressStep (..),
    SundaeAMMStep (..),
    StepResult (..),
    toTxOut,
    mkFlowStep,
) where

import Cardano.Api qualified as C
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Generics (Generic)
import PlutusTx qualified
import Privy.API.SerialisedPlutusDatum (SerialisedPlutusDatum (..))
import Privy.API.Steps.MinSwap (MinSwapStep (..), buildMinSwapStep)
import Privy.API.Steps.MuesliSwap (MuesliSwapStep (..), buildMuesliSwapStep)
import Privy.API.Steps.Pulse (PulseStep (..), buildPulseStep)
import Privy.API.Steps.SendToAddress (SendToAddressStep (..), buildSendToAddressStep)
import Privy.API.Steps.StepResult (StepResult (..), toTxOut)
import Privy.API.Steps.SundaeAMM (SundaeAMMStep (..), buildSundaeAMMStep)
import Privy.Env.Operator (OperatorEnv)

data TxFlowStep
    = SendToAddress SendToAddressStep
    | MinSwap MinSwapStep
    | Pulse PulseStep
    | MuesliSwap MuesliSwapStep
    | SundaeAMM SundaeAMMStep
    deriving stock (Eq, Show, Generic)

txFlowStepOptions :: Aeson.Options
txFlowStepOptions =
    Aeson.defaultOptions
        { Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 0
        , Aeson.sumEncoding = Aeson.ObjectWithSingleField
        }

instance ToJSON TxFlowStep where
    toJSON = Aeson.genericToJSON txFlowStepOptions
    toEncoding = Aeson.genericToEncoding txFlowStepOptions

instance FromJSON TxFlowStep where
    parseJSON = Aeson.genericParseJSON txFlowStepOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 0, Aeson.sumEncoding = Aeson.ObjectWithSingleField}) ''TxFlowStep)

instance Schema.ToSchema TxFlowStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions txFlowStepOptions)

mkFlowStep ::
    forall era.
    OperatorEnv era ->
    StepResult C.ScriptData ->
    TxFlowStep ->
    StepResult C.ScriptData
mkFlowStep operatorEnv result = \case
    SendToAddress m -> serialisedDatumStepResult $ buildSendToAddressStep m
    MinSwap m -> toScriptDataStepResult $ buildMinSwapStep result m
    Pulse m -> toScriptDataStepResult $ buildPulseStep operatorEnv result m
    MuesliSwap m -> toScriptDataStepResult $ buildMuesliSwapStep result m
    SundaeAMM m -> toScriptDataStepResult $ buildSundaeAMMStep operatorEnv result m

serialisedDatumStepResult :: StepResult SerialisedPlutusDatum -> StepResult C.ScriptData
serialisedDatumStepResult = fmap unSerialisedPlutusDatum

toScriptDataStepResult ::
    (PlutusTx.ToData a) =>
    StepResult a ->
    StepResult C.ScriptData
toScriptDataStepResult = fmap (C.fromPlutusData . PlutusTx.toData . PlutusTx.toBuiltinData)
