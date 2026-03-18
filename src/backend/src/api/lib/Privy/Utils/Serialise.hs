module Privy.Utils.Serialise (
    SerialiseRawBytes (..),
) where

import Cardano.Api qualified as C
import Codec.Serialise (Serialise (..))
import Codec.Serialise.Decoding qualified as Decoding
import Codec.Serialise.Encoding qualified as Encoding
import Data.Proxy (Proxy (..))

newtype SerialiseRawBytes a = SerialiseRawBytes {unSerialiseRawBytes :: a}

instance (C.SerialiseAsRawBytes a) => Serialise (SerialiseRawBytes a) where
    encode = Encoding.encodeBytes . C.serialiseToRawBytes . unSerialiseRawBytes
    decode = SerialiseRawBytes <$> (Decoding.decodeBytes >>= either (fail . show) pure . C.deserialiseFromRawBytes (C.proxyToAsType Proxy))
