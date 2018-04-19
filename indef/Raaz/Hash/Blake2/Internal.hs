{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# CFILES raaz/hash/sha1/portable.c    #-}

-- | Internal types and function for blake2 hashes.
module Raaz.Hash.Blake2.Internal
       ( -- * The blake2 types
         BLAKE2b, BLAKE2s
       , Blake2bMem(..), Blake2sMem(..)
       , blake2Pad
       ) where

import           Control.Applicative
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Reader ( withReaderT     )
import           Data.Bits                  ( xor             )
import           Data.Proxy
import           Data.String
import           Data.Word                  ( Word64, Word32  )
import           Foreign.Storable           ( Storable(..) )
import           Prelude      hiding        ( zipWith      )

import           Raaz.Core
import           Raaz.Core.Transfer

----------------------------- The blake2 type ---------------------------------

-- | The BLAKE2 type.
newtype BLAKE2 w = BLAKE2 (Tuple 8 w)
               deriving (Eq, Equality, Storable, EndianStore)

-- | Word type for Blake2b
type Word2b = LE Word64

-- | Word type for Blake2s
type Word2s = LE Word32

-- | The BLAKE2b hash type.
type BLAKE2b = BLAKE2 Word2b

-- | The BLAKE2s hash type.
type BLAKE2s = BLAKE2 Word2s

instance Encodable BLAKE2b
instance Encodable BLAKE2s


instance IsString BLAKE2b where
  fromString = fromBase16

instance IsString BLAKE2s where
  fromString = fromBase16

instance Show BLAKE2b where
  show =  showBase16

instance Show BLAKE2s where
  show =  showBase16

instance Primitive BLAKE2b where
  type BlockSize BLAKE2b      = 128
  type Key BLAKE2b            = ()
  type Digest BLAKE2b         = BLAKE2b

instance Primitive BLAKE2s where
  type BlockSize BLAKE2s      = 64
  type Key BLAKE2s            = ()
  type Digest BLAKE2s         = BLAKE2s

-- | The initial value to start the blake2b hashing. This is equal to
-- the iv `xor` the parameter block.
hash2b0 :: BLAKE2b
hash2b0 = BLAKE2 $ unsafeFromList [ 0x6a09e667f3bcc908 `xor` 0x01010040
                                  , 0xbb67ae8584caa73b
                                  , 0x3c6ef372fe94f82b
                                  , 0xa54ff53a5f1d36f1
                                  , 0x510e527fade682d1
                                  , 0x9b05688c2b3e6c1f
                                  , 0x1f83d9abfb41bd6b
                                  , 0x5be0cd19137e2179
                                  ]

-- | The initial value to start the blake2b hashing. This is equal to
-- the iv `xor` the parameter block.
hash2s0 :: BLAKE2s
hash2s0 = BLAKE2 $ unsafeFromList [ 0x6a09e667 `xor` 0x01010020
                                  , 0xbb67ae85
                                  , 0x3c6ef372
                                  , 0xa54ff53a
                                  , 0x510e527f
                                  , 0x9b05688c
                                  , 0x1f83d9ab
                                  , 0x5be0cd19
                                  ]

---------------------------------- Memory element for BLAKE2b -----------------------

-- | Memory element for BLAKE2b implementations.
data Blake2bMem = Blake2bMem { blake2bCell :: MemoryCell BLAKE2b
                             , uLengthCell :: MemoryCell (BYTES Word64)
                             , lLengthCell :: MemoryCell (BYTES Word64)
                             }


instance Memory Blake2bMem where
  memoryAlloc     = Blake2bMem <$> memoryAlloc <*> memoryAlloc <*> memoryAlloc
  unsafeToPointer = unsafeToPointer . blake2bCell

instance Initialisable Blake2bMem () where
  initialise _ = do withReaderT blake2bCell  $ initialise hash2b0
                    withReaderT uLengthCell  $ initialise (0 :: BYTES Word64)
                    withReaderT lLengthCell  $ initialise (0 :: BYTES Word64)

instance Extractable Blake2bMem BLAKE2b where
  extract = withReaderT blake2bCell extract

---------------------------------- Memory element for BLAKE2b -----------------------

-- | Memory element for BLAKE2s implementations.
data Blake2sMem = Blake2sMem { blake2sCell :: MemoryCell BLAKE2s
                             , lengthCell  :: MemoryCell (BYTES Word64)
                             }

instance Memory Blake2sMem where
  memoryAlloc     = Blake2sMem <$> memoryAlloc <*> memoryAlloc
  unsafeToPointer = unsafeToPointer . blake2sCell

instance Initialisable Blake2sMem () where
  initialise _ = do withReaderT blake2sCell $ initialise hash2s0
                    withReaderT lengthCell  $ initialise (0 :: BYTES Word64)

instance Extractable Blake2sMem BLAKE2s where
  extract = withReaderT blake2sCell extract

----------------------- Padding for Blake code ------------------------------

-- | The generic blake2 padding algorithm.
blake2Pad :: (Primitive prim, MonadIO m)
          => Proxy prim  -- ^ the primitive (BLAKE2b or BLAKE2s).
          -> BYTES Int   -- ^ length of the message
          -> WriteM m
blake2Pad primProxy = padWrite 0 (blocksOf 1 primProxy) . skipWrite
