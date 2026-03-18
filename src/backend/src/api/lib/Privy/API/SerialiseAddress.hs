{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Privy.API.SerialiseAddress (
    SerialiseAddress (..),
) where

import Cardano.Api qualified as C
import Codec.Serialise (Serialise (..))
import Control.Lens ((&), (?~))
import Control.Monad (mzero)
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.OpenApi (ToSchema (..))
import Data.OpenApi.Internal (OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.ParamSchema (ToParamSchema (..))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Typeable (Typeable)
import Database.Beam (FromBackendRow, HasSqlEqualityCheck (..))
import Database.Beam.Backend.SQL.SQL92 (HasSqlValueSyntax (..))
import Database.Beam.Migrate.Generics (HasDefaultSqlDataType (..))
import Database.Beam.Postgres (Postgres)
import Database.Beam.Postgres.Syntax (PgValueSyntax)
import Database.Beam.Sqlite.Connection (Sqlite)
import Database.Beam.Sqlite.Syntax (SqliteValueSyntax)
import Database.PostgreSQL.Simple.FromField qualified as Postgres
import Database.PostgreSQL.Simple.ToField qualified as Postgres
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.Ok (Ok (..))
import Database.SQLite.Simple.ToField (ToField (..))
import Privy.Orphans ()
import Privy.Utils.Serialise (SerialiseRawBytes (..))
import Servant.API (FromHttpApiData (..), ToHttpApiData (..))

newtype SerialiseAddress a = SerialiseAddress {unSerialiseAddress :: a}
    deriving newtype (Eq, Show)
    deriving (Serialise) via (SerialiseRawBytes a)

instance (Typeable a) => TypeScript (SerialiseAddress a) where
    getTypeScriptType _ = "string"

instance ToParamSchema (SerialiseAddress a) where
    toParamSchema _proxy =
        mempty
            & L.type_ ?~ OpenApiString
            & L.description ?~ "bech32-serialised cardano address"
            & L.example ?~ "addr1q9d42egme33z960rr8vlnt69lpmythdpm7ydk2e6k5nj5ghay9rg60vw49kejfah76sqeh4yshlsntgg007y0wgjlfwju6eksr"

deriving newtype instance ToJSON (SerialiseAddress (C.Address C.ShelleyAddr))
deriving newtype instance FromJSON (SerialiseAddress (C.Address C.ShelleyAddr))
deriving newtype instance ToSchema (SerialiseAddress (C.Address C.ShelleyAddr))

instance FromField (SerialiseAddress (C.Address C.ShelleyAddr)) where
    fromField f =
        SerialiseAddress
            <$> (maybe (Errors []) Ok . C.deserialiseAddress (C.proxyToAsType Proxy) =<< fromField f)

instance Postgres.FromField (SerialiseAddress (C.Address C.ShelleyAddr)) where
    fromField f =
        Postgres.fromField @Text f >>= \conversion _mbs -> (conversion >>= maybe mzero (pure . SerialiseAddress) . C.deserialiseAddress (C.proxyToAsType Proxy))

instance ToField (SerialiseAddress (C.Address C.ShelleyAddr)) where
    toField (SerialiseAddress addr) = toField (C.serialiseAddress addr)

instance Postgres.ToField (SerialiseAddress (C.Address C.ShelleyAddr)) where
    toField (SerialiseAddress addr) = Postgres.toField (C.serialiseAddress addr)

instance FromBackendRow Sqlite (SerialiseAddress (C.Address C.ShelleyAddr))

instance FromBackendRow Postgres (SerialiseAddress (C.Address C.ShelleyAddr))

instance HasSqlValueSyntax SqliteValueSyntax (SerialiseAddress (C.Address C.ShelleyAddr)) where
    sqlValueSyntax (SerialiseAddress addr) = sqlValueSyntax (C.serialiseAddress addr)

instance HasSqlValueSyntax PgValueSyntax (SerialiseAddress (C.Address C.ShelleyAddr)) where
    sqlValueSyntax (SerialiseAddress addr) = sqlValueSyntax (C.serialiseAddress addr)

instance HasDefaultSqlDataType Sqlite (SerialiseAddress (C.Address C.ShelleyAddr)) where
    defaultSqlDataType _ = defaultSqlDataType (Proxy :: Proxy Text)

instance HasDefaultSqlDataType Postgres (SerialiseAddress (C.Address C.ShelleyAddr)) where
    defaultSqlDataType _ = defaultSqlDataType (Proxy :: Proxy Text)

instance HasSqlEqualityCheck Sqlite (SerialiseAddress (C.Address C.ShelleyAddr))

instance HasSqlEqualityCheck Postgres (SerialiseAddress (C.Address C.ShelleyAddr))

instance (C.SerialiseAddress a) => FromHttpApiData (SerialiseAddress a) where
    parseUrlPiece =
        maybe (Left "Failed to deserialise address") (Right . SerialiseAddress) . C.deserialiseAddress (C.proxyToAsType Proxy)

instance (C.SerialiseAddress a) => ToHttpApiData (SerialiseAddress a) where
    toUrlPiece = C.serialiseAddress . unSerialiseAddress
