{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Privy.Orphans () where

import Cardano.Api qualified as C
import Control.Lens ((&), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.OpenApi.Internal (NamedSchema (..), OpenApiType (OpenApiInteger, OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.Schema (ToSchema (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as Enc
import Servant.API.ContentTypes (NoContent)

instance ToSchema (C.Address C.ShelleyAddr) where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "Address") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "bech32-encoded cardano address"
                    & L.example ?~ "addr_test1qpju2uhn72ur6j5alln6nz7dqcgcjal7xjaw7lwdjdaex4qhr3xpz63fjwvlpsnu8efnhfdja78d3vkv8ks6ac09g3usemu2yl"

instance TypeScript NoContent where
    getTypeScriptType _ = "{}"

instance ToJSON C.AssetId where
    toJSON = Aeson.String . assetIdToText

instance FromJSON C.AssetId where
    parseJSON = Aeson.withText "AssetId" (either fail pure . textToAssetId)

instance TypeScript C.AssetId where
    getTypeScriptType _ = "string"

instance ToSchema C.AssetId where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "AssetId") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "Cardano asset ID, either 'lovelace' or POLICY_ID.TOKEN_NAME"

instance TypeScript C.Quantity where
    getTypeScriptType _ = "number"

instance ToSchema C.Quantity where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "Quantity") $
                mempty
                    & L.type_ ?~ OpenApiInteger

assetIdToText :: C.AssetId -> T.Text
assetIdToText = \case
    C.AdaAssetId -> "lovelace"
    C.AssetId policy assetName ->
        C.serialiseToRawBytesHexText policy
            <> "."
            <> C.serialiseToRawBytesHexText assetName

textToAssetId :: T.Text -> Either String C.AssetId
textToAssetId text = case text of
    "lovelace" -> pure C.AdaAssetId
    (T.breakOn "." -> (policyText, assetText')) -> do
        let assetText = T.drop 1 assetText'
        C.AssetId
            <$> either (Left . show) pure (C.deserialiseFromRawBytesHex (Enc.encodeUtf8 policyText))
            <*> either (Left . show) pure (C.deserialiseFromRawBytesHex (Enc.encodeUtf8 assetText))
