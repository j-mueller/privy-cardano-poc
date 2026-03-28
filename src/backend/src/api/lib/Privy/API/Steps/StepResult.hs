module Privy.API.Steps.StepResult (
    StepResult (..),
    toTxOut,
) where

import Cardano.Api qualified as C
import Control.Lens qualified as L
import Convex.CardanoApi.Lenses qualified as L

data StepResult a
    = StepResult
    { srDatum :: Maybe a
    , srAddress :: C.Address C.ShelleyAddr
    , srValue :: C.Value
    }
    deriving stock (Eq, Show, Functor)

toTxOut ::
    forall era.
    (C.IsBabbageBasedEra era) =>
    StepResult C.ScriptData ->
    C.TxOut C.CtxTx era
toTxOut StepResult{srDatum, srAddress, srValue} =
    C.TxOut
        (C.shelleyAddressInEra C.shelleyBasedEra srAddress)
        (L.review L._TxOutValue srValue)
        txOutDatum
        C.ReferenceScriptNone
  where
    txOutDatum =
        case srDatum of
            Just dt ->
                C.TxOutDatumInline
                    C.babbageBasedEra
                    (C.unsafeHashableScriptData dt)
            Nothing ->
                C.TxOutDatumNone
