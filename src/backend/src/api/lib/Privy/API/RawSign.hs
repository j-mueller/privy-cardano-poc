{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Backend raw_sign endpoint that forwards signing requests to Privy using server-side app credentials.
module Privy.API.RawSign (
    RawSignArgs (..),
    RawSignHashFunction (..),
    RawSignResponse (..),
    RawSignError (..),
    AsRawSignError (..),
    API,
    serve,
) where

import Control.Exception (try)
import Control.Lens (makeClassyPrisms, review, (&), (?~))
import Control.Monad (when)
import Control.Monad.Except (MonadError, throwError)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.TypeScript.TH (TypeScript (..), deriveTypeScript)
import Data.ByteArray.Encoding (Base (Base64), convertToBase)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isHexDigit)
import Data.OpenApi (NamedSchema (..))
import Data.OpenApi.Internal (OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Enc
import Data.Text.Encoding.Error qualified as EncErr
import GHC.Generics (Generic)
import Network.HTTP.Client (
    HttpException,
    RequestBody (RequestBodyLBS),
    httpLbs,
    method,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
 )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (hAccept, hAuthorization, hContentType)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import Servant.API (JSON, Post, ReqBody, type (:>))
import Servant.Server (ServerT)
import System.Environment (lookupEnv)

data RawSignHashFunction
    = Sha256
    | Blake2b256
    | Keccak256
    deriving stock (Eq, Show, Generic)

instance ToJSON RawSignHashFunction where
    toJSON = Aeson.String . hashFunctionToText

instance FromJSON RawSignHashFunction where
    parseJSON =
        Aeson.withText "RawSignHashFunction" $ \case
            "sha256" -> pure Sha256
            "blake2b256" -> pure Blake2b256
            "keccak256" -> pure Keccak256
            _ -> fail "Unsupported hash function"

instance TypeScript RawSignHashFunction where
    getTypeScriptType _ = "'sha256' | 'blake2b256' | 'keccak256'"

instance Schema.ToSchema RawSignHashFunction where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "RawSignHashFunction") $
                mempty
                    & L.type_ ?~ OpenApiString

hashFunctionToText :: RawSignHashFunction -> Text
hashFunctionToText = \case
    Sha256 -> "sha256"
    Blake2b256 -> "blake2b256"
    Keccak256 -> "keccak256"

data RawSignArgs
    = RawSignArgs
    { rsaWalletId :: Text
    , rsaPayloadHex :: Maybe Text
    , rsaTransactionHex :: Maybe Text
    , rsaAuthorizationSignature :: Text
    , rsaHashFunction :: Maybe RawSignHashFunction
    }
    deriving stock (Eq, Show, Generic)

rawSignArgsOptions :: Aeson.Options
rawSignArgsOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3
        }

instance ToJSON RawSignArgs where
    toJSON = Aeson.genericToJSON rawSignArgsOptions
    toEncoding = Aeson.genericToEncoding rawSignArgsOptions

instance FromJSON RawSignArgs where
    parseJSON = Aeson.genericParseJSON rawSignArgsOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''RawSignArgs)

instance Schema.ToSchema RawSignArgs where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions rawSignArgsOptions)

newtype RawSignResponse
    = RawSignResponse
    { rsrSignature :: Text
    }
    deriving stock (Eq, Show, Generic)

rawSignResponseOptions :: Aeson.Options
rawSignResponseOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3
        }

instance ToJSON RawSignResponse where
    toJSON = Aeson.genericToJSON rawSignResponseOptions
    toEncoding = Aeson.genericToEncoding rawSignResponseOptions

instance FromJSON RawSignResponse where
    parseJSON = Aeson.genericParseJSON rawSignResponseOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''RawSignResponse)

instance Schema.ToSchema RawSignResponse where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions rawSignResponseOptions)

newtype PrivyRawSignResponse
    = PrivyRawSignResponse
    { prsData :: PrivyRawSignData
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON PrivyRawSignResponse where
    parseJSON = Aeson.genericParseJSON Aeson.defaultOptions

newtype PrivyRawSignData
    = PrivyRawSignData
    { prdSignature :: Text
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON PrivyRawSignData where
    parseJSON = Aeson.genericParseJSON Aeson.defaultOptions

data RawSignError
    = MissingPrivyAppId
    | MissingPrivyAppSecret
    | MissingWalletId
    | MissingPayloadHexOrTransactionHex
    | MissingAuthorizationSignature
    | InvalidHexPayload Text
    | PrivyRequestFailed HttpException
    | PrivyErrorResponse Int Text
    | PrivyDecodeError String
    deriving stock (Show)

makeClassyPrisms ''RawSignError

type API = "raw_sign" :> ReqBody '[JSON] RawSignArgs :> Post '[JSON] RawSignResponse

serve :: forall err m. (MonadIO m, MonadError err m, AsRawSignError err) => ServerT API m
serve = rawSign

rawSign :: forall err m. (MonadIO m, MonadError err m, AsRawSignError err) => RawSignArgs -> m RawSignResponse
rawSign RawSignArgs{rsaWalletId, rsaPayloadHex, rsaTransactionHex, rsaAuthorizationSignature, rsaHashFunction} = do
    appId <- getPrivyAppId
    appSecret <- getPrivyAppSecret

    when (Text.null (Text.strip rsaWalletId)) $
        throwError (review _MissingWalletId ())

    when (Text.null (Text.strip rsaAuthorizationSignature)) $
        throwError (review _MissingAuthorizationSignature ())

    params <- case (rsaPayloadHex, rsaTransactionHex) of
        (Just payloadHex, _) -> do
            normalizedHash <- normalizeHex payloadHex
            pure $ Aeson.object ["hash" Aeson..= ("0x" <> normalizedHash)]
        (Nothing, Just txHex) -> do
            normalizedTx <- normalizeHex txHex
            txBytes <-
                liftEitherInvalidHex $
                    Base16.decode (Enc.encodeUtf8 normalizedTx)
            let txBase64 = Enc.decodeUtf8 (convertToBase Base64 txBytes)
            pure $
                Aeson.object
                    [ "bytes" Aeson..= txBase64
                    , "encoding" Aeson..= ("base64" :: Text)
                    , "hash_function" Aeson..= hashFunctionToText (maybe Blake2b256 id rsaHashFunction)
                    ]
        (Nothing, Nothing) -> throwError (review _MissingPayloadHexOrTransactionHex ())

    let walletIdEncoded = Enc.decodeUtf8 $ urlEncode True (Enc.encodeUtf8 rsaWalletId)
        url = "https://api.privy.io/v1/wallets/" <> walletIdEncoded <> "/raw_sign"
        requestBodyJson = Aeson.encode $ Aeson.object ["params" Aeson..= params]
        basicCredentials = Enc.decodeUtf8 $ convertToBase Base64 (Enc.encodeUtf8 (appId <> ":" <> appSecret))

    baseRequest <- liftIO $ parseRequest (Text.unpack url)

    let request =
            baseRequest
                { method = "POST"
                , requestBody = RequestBodyLBS requestBodyJson
                , requestHeaders =
                    [ (hAccept, "application/json")
                    , (hContentType, "application/json")
                    , ("privy-app-id", Enc.encodeUtf8 appId)
                    , (hAuthorization, Enc.encodeUtf8 ("Basic " <> basicCredentials))
                    , ("privy-authorization-signature", Enc.encodeUtf8 rsaAuthorizationSignature)
                    ]
                }

    manager <- liftIO newTlsManager
    responseResult <- liftIO $ try @HttpException (httpLbs request manager)
    response <-
        case responseResult of
            Left httpError -> throwError (review _PrivyRequestFailed httpError)
            Right okResponse -> pure okResponse

    let status = statusCode (responseStatus response)
        body = responseBody response

    if status >= 200 && status < 300
        then case Aeson.eitherDecode body of
            Left decodeErr -> throwError (review _PrivyDecodeError decodeErr)
            Right PrivyRawSignResponse{prsData = PrivyRawSignData{prdSignature}} ->
                pure $ RawSignResponse{rsrSignature = prdSignature}
        else throwError (review _PrivyErrorResponse (status, decodeErrorText body))

getPrivyAppId :: forall err m. (MonadIO m, MonadError err m, AsRawSignError err) => m Text
getPrivyAppId = do
    appIdEnv <- liftIO $ lookupEnv "PRIVY_APP_ID"
    case appIdEnv of
        Nothing -> throwError (review _MissingPrivyAppId ())
        Just val -> pure (Text.pack val)

getPrivyAppSecret :: forall err m. (MonadIO m, MonadError err m, AsRawSignError err) => m Text
getPrivyAppSecret = do
    appSecretEnv <- liftIO $ lookupEnv "PRIVY_APP_SECRET"
    case appSecretEnv of
        Nothing -> throwError (review _MissingPrivyAppSecret ())
        Just val -> pure (Text.pack val)

liftEitherInvalidHex :: forall err m a. (MonadError err m, AsRawSignError err) => Either String a -> m a
liftEitherInvalidHex =
    either
        (const $ throwError (review _InvalidHexPayload "Payload hex contains non-hex characters"))
        pure

normalizeHex :: forall err m. (MonadError err m, AsRawSignError err) => Text -> m Text
normalizeHex value = do
    let trimmed = Text.strip value
        normalized
            | "0x" `Text.isPrefixOf` trimmed = Text.drop 2 trimmed
            | "0X" `Text.isPrefixOf` trimmed = Text.drop 2 trimmed
            | otherwise = trimmed

    when (Text.null normalized) $
        throwError (review _InvalidHexPayload "Payload hex cannot be empty")

    when (odd (Text.length normalized)) $
        throwError (review _InvalidHexPayload "Payload hex must contain an even number of characters")

    if Text.all isHexDigit normalized
        then pure (Text.toLower normalized)
        else throwError (review _InvalidHexPayload "Payload hex contains non-hex characters")

decodeErrorText :: LBS.ByteString -> Text
decodeErrorText body =
    case Aeson.decode body of
        Just (Aeson.Object obj) ->
            case AesonKeyMap.lookup (AesonKey.fromString "error") obj of
                Just (Aeson.String errText) -> errText
                _ -> Enc.decodeUtf8With EncErr.lenientDecode (LBS.toStrict body)
        _ -> Enc.decodeUtf8With EncErr.lenientDecode (LBS.toStrict body)
