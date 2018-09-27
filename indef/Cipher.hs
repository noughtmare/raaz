{-# LANGUAGE TypeFamilies #-}
-- | This module exposes all the ciphers provided by raaz. The
-- interface here is pretty low level and it is usually the case that
-- you would not need to work at this level of detail.
module Cipher
       ( -- * Ciphers
         -- $cipherdoc$
         StreamCipher(..)
       ) where

import           Data.ByteString                  ( ByteString )
import           Data.Proxy                       ( Proxy      )
import           Raaz.Core
import           Raaz.Primitive.ChaCha20.Internal ( ChaCha20   )
import qualified ChaCha20.Utils

-- $cipherdoc$
--
-- The raaz library exposes symmetric key encryption using instances
-- of the class `Cipher`. For a cipher @c@, the type family @`Key` c@
-- gives the type of its key. As of now, we only support the safe
-- usage of stream ciphers. Encryption and Decryption are the same for
-- stream ciphers and we call this combinator `transform`. Block
-- ciphers do not have a natural way to handle streams that are of
-- size less than their block size. A future release will handle these
-- issues.
--
-- If you are thinking of encryption using private keys consider
-- encrypted-authenticated modes. Currently we do not have support for
-- this either but hopefully this will also be fixed soon.
--
-- TODO: Fix the above documentation when it is done.

-- | Primitives that are stream ciphers.
class (Primitive c, Digest c ~ ()) => StreamCipher c where
  transform :: Proxy c -> Key c -> ByteString -> ByteString

instance StreamCipher ChaCha20 where
  transform _ key = fst . ChaCha20.Utils.transformAndDigest key
