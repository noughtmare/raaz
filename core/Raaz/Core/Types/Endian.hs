{-# LANGUAGE CPP                        #-}
{-# LANGUAGE ForeignFunctionInterface   #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE TypeFamilies               #-}

-- | Endian safe types.
module Raaz.Core.Types.Endian
       ( -- * Endianess aware types.
         -- $endianness$
         EndianStore(..), copyFromBytes, copyToBytes
       -- ** Endian explicit word types.
       , LE(..), BE(..), littleEndian, bigEndian
       -- ** Helper functions for endian aware storing and loading.
       , storeAt, storeAtIndex
       , loadFrom, loadFromIndex
       ) where


import           Control.DeepSeq             ( NFData)
import           Data.Typeable
import           Data.Vector.Unboxed         ( MVector(..), Vector, Unbox )
import           Foreign.Ptr                 ( castPtr, Ptr )
import           Foreign.Storable            ( Storable, peek, poke )

import qualified Data.Vector.Generic         as GV
import qualified Data.Vector.Generic.Mutable as GVM

import           Raaz.Core.Prelude
import           Raaz.Core.Types.Copying
import           Raaz.Core.Types.Pointer
import           Raaz.Core.Types.Equality

#include "MachDeps.h"

-- $endianness$
--
-- Cryptographic primitives often consider their input as an array of
-- words of a particular endianness. Endianness is only relevant when
-- serialising to (or de-serialising from) their encoding to the
-- outside world. Raaz strives to use types to provide an endian
-- agnostic interface to all data that is relevant to the outside
-- world.
--
-- The starting point of an endian agnostic interface is the class
-- `EndianStore`. Instances of this class support an endian agnostic
-- `load` and `store`. Endian adjusted copying is also provided for
-- these types through the helper functions `copyFromBytes` and
-- `copyToBytes`.
--
-- It is tedious to think about endianness for each new type one might
-- encounter. As before, we have a top down approach to defining such
-- an interface. To start with, the library exposes endian aware
-- variants of `Word32` and `Word64` and functions @littleEndian@ and
-- @bigEndian@ for conversions. The `Tuple` type inherits the
-- endianness of its element type, i.e for example @Tuple 10 (LE
-- Word32)@ when loded (or stored) will load (or store) 10 32-bit
-- words assuming that the words are expressed in little endian. Other
-- types are then built out of these endian aware types. For example,
-- cryptographic type `SHA512` is defined as.
--
-- >
-- > newtype SHA512 = SHA512 (Tuple 8 (BE Word64))
-- >                      deriving (Equality, Eq, Storable, EndianStore)
-- >
--

-- | This class captures types which provides an endian agnostic way
-- of loading from and storing to data buffers. Any multi-byte type
-- that is meant to be serialised to the outside world should be an
-- instance of this class. When defining the `load`, `store`,
-- `adjustEndian` member functions, care should be taken to ensure
-- proper endian conversion.
--
class Storable w => EndianStore w where

  -- | The action @store ptr w@ stores @w@ at the location pointed by
  -- @ptr@.  Endianness of the type @w@ is taken care of when storing.
  -- For example, irrespective of the endianness of the machine,
  -- @store ptr (0x01020304 :: BE Word32)@ will store the bytes
  -- @0x01@, @0x02@, @0x03@, @0x04@ respectively at locations @ptr@,
  -- @ptr +1@, @ptr+2@ and @ptr+3@. On the other hand @store ptr
  -- (0x01020304 :: LE Word32)@ would store @0x04@, @0x03@, @0x02@,
  -- @0x01@ at the above locations.

  store :: Ptr w   -- ^ the location.
        -> w       -- ^ value to store
        -> IO ()

  -- | The action @load ptr@ loads the value stored at the @ptr@. Like
  -- store, it takes care of the endianness of the data type.  For
  -- example, if @ptr@ points to a buffer containing the bytes @0x01@,
  -- @0x02@, @0x03@, @0x04@, irrespective of the endianness of the
  -- machine, @load ptr :: IO (BE Word32)@ will load the vale
  -- @0x01020304@ of type @BE Word32@ and @load ptr :: IO (LE Word32)@
  -- will load @0x04030201@ of type @LE Word32@.
  load  :: Ptr w -> IO w

  -- | The action @adjustEndian ptr n@ adjusts the encoding of bytes
  -- stored at the location @ptr@ to conform with the endianness of
  -- the underlying data type. For example, assume that @ptr@ points
  -- to a buffer containing the bytes @0x01 0x02 0x03 0x04@, and we
  -- are on a big endian machine, then @adjustEndian (ptr :: Ptr (LE
  -- Word32)) 1@ will result in @ptr@ pointing to the sequence @0x04
  -- 0x03 0x02 0x01@. On the other hand if we were on a little endian
  -- machine, the sequence should remain the same.  In particular, the
  -- following equalities should hold.
  --
  -- >
  -- > store ptr w          = poke ptr w >> adjustEndian ptr 1
  -- >
  --
  -- Similarly the value loaded by @load ptr@ should be same as the
  -- value returned by @adjustEndian ptr 1 >> peak ptr@, although the
  -- former does not change the contents stored at @ptr@ where as the
  -- latter might does modify the contents pointed by @ptr@ if the
  -- endianness of the machine and the time do not agree.
  --
  -- The action @adjustEndian ptr n >> adjustEndian ptr n @ should be
  -- equivalent to @return ()@.
  --
  adjustEndian :: Ptr w  -- ^ buffer pointers,
               -> Int    -- ^ how many w's are present,
               -> IO ()


instance EndianStore Word8 where
  store                  = poke
  load                   = peek
  adjustEndian  _ _      = return ()

instance EndianStore w => EndianStore (BYTES w) where
  store ptr (BYTES w)  = store (castPtr ptr) w
  load                 = fmap BYTES . load . castPtr
  adjustEndian         = adjustEndian . castToPtrW
    where castToPtrW :: Ptr (BYTES w) -> Ptr w
          castToPtrW = castPtr

-- | Store the given value at an offset from the crypto pointer. The
-- offset is given in type safe units.
storeAt :: ( EndianStore w
           , LengthUnit offset
           )
        => Ptr w     -- ^ the pointer
        -> offset    -- ^ the absolute offset in type safe length units.
        -> w         -- ^ value to store
        -> IO ()
{-# INLINE storeAt #-}
storeAt ptr = store . movePtr ptr

-- | Store the given value as the @n@-th element of the array
-- pointed by the crypto pointer.
storeAtIndex :: EndianStore w
             => Ptr w          -- ^ the pointer to the first element of the
                               -- array
             -> Int            -- ^ the index of the array
             -> w              -- ^ the value to store
             -> IO ()
{-# INLINE storeAtIndex #-}
storeAtIndex cptr index w = storeAt cptr offset w
  where offset  = toEnum index * sizeOf (pure w)


-- | Load the @n@-th value of an array pointed by the crypto pointer.
loadFromIndex :: EndianStore w
              => Ptr w   -- ^ the pointer to the first element of
                         -- the array
              -> Int     -- ^ the index of the array
              -> IO w
{-# INLINE loadFromIndex #-}
loadFromIndex cptr index = load $ shiftPtr cptr
  where shiftPtr :: Storable w => Ptr w -> Ptr w
        shiftPtr ptr = movePtr ptr (toEnum index * sizeOf (getProxy ptr))
        getProxy    :: Ptr w -> Proxy w
        getProxy    = const Proxy
-- | Load from a given offset. The offset is given in type safe units.
loadFrom :: ( EndianStore w
            , LengthUnit offset
            )
         => Ptr w    -- ^ the pointer
         -> offset   -- ^ the offset
         -> IO w
{-# INLINE loadFrom #-}
loadFrom ptr = load . movePtr ptr

-- | For the type @w@, the action @copyFromBytes dest src n@ copies @n@-elements from
-- @src@ to @dest@. Copy performed by this combinator accounts for the
-- endianness of the data in @dest@ and is therefore /not/ a mere copy
-- of @n * sizeOf(w)@ bytes. This action does not modify the @src@
-- pointer in any way.

copyFromBytes :: EndianStore w
              => Dest (Ptr w)
              -> Src  Pointer
              -> Int          -- ^ How many items.
              -> IO ()
copyFromBytes dest@(Dest ptr) src n =  memcpy (castPtr <$> dest) src (sz dest Proxy)
                                       >> adjustEndian ptr n
  where sz          :: Storable w => Dest (Ptr w) -> Proxy w -> BYTES Int
        sz _ wProxy =  sizeOf wProxy * toEnum n

-- | Similar to @copyFromBytes@ but the transfer is done in the other direction. The copy takes
-- care of performing the appropriate endian encoding.
copyToBytes :: EndianStore w
            => Dest Pointer
            -> Src (Ptr w)
            -> Int
            -> IO ()
copyToBytes dest@(Dest dptr) src n =  memcpy dest  (castPtr <$> src) (sz src undefined)
                                     >> adjust src (castPtr dptr)
  where adjust :: EndianStore w => Src (Ptr w) -> Ptr w -> IO ()
        adjust _ ptr = adjustEndian ptr n

        sz     :: Storable w => Src (Ptr w) -> Proxy w -> BYTES Int
        sz _ w =  sizeOf w * toEnum n


{-
Developers notes:
-----------------

Make sure that the endian encoded version does not have any
performance penalty. We may have to stare at the core code generated
by ghc.

-}

-- | Little endian version of the word type @w@
newtype LE w = LE { unLE :: w }
    deriving ( Bounded, Enum, Read, Show
             , Integral, Num, Real, Eq, Equality, Ord
             , Bits, Storable, Typeable, NFData
             )

instance Functor LE where
  fmap f = LE . f . unLE

-- | Big endian version of the word type @w@
newtype BE w = BE { unBE :: w }
    deriving ( Bounded, Enum, Read, Show
             , Integral, Num, Real, Eq, Equality, Ord
             , Bits, Storable, Typeable, NFData
             )

instance Functor BE where
  fmap f = BE . f . unBE

-- | Convert to the little endian variant.
littleEndian :: w -> LE w
{-# INLINE littleEndian #-}
littleEndian = LE

-- | Convert to the big endian variants.
bigEndian :: w -> BE w
{-# INLINE bigEndian #-}
bigEndian = BE

---------------- The foreign function calls ----------------------

foreign import ccall unsafe "raaz/core/endian.h raazSwap32Array"
  c_Swap32Array :: Ptr Word32 -> Int -> IO ()
foreign import ccall unsafe "raaz/core/endian.h raazSwap64Array"
  c_Swap64Array :: Ptr Word64 -> Int -> IO ()

#ifdef WORDS_BIGENDIAN

unLEPtr :: Ptr (LE w) -> Ptr w
unLEPtr = castPtr

instance EndianStore (LE Word32) where
  load  ptr    = fmap byteSwap32 <$>  peek ptr
  store ptr    = poke ptr  . fmap byteSwap32
  adjustEndian = c_Swap32Array . unLEPtr


instance EndianStore (LE Word64) where
  load  ptr     = fmap byteSwap64    <$> peek ptr
  store ptr     = poke ptr  . fmap byteSwap64
  adjustEndian  = c_Swap64Array . unLEPtr


instance EndianStore (BE Word32) where
  load             = peek
  store            = poke
  adjustEndian _ _ = return ()

instance EndianStore (BE Word64) where
  load             = peek
  store            = poke
  adjustEndian _ _ = return ()

# else

unBEPtr :: Ptr (BE w) -> Ptr w
unBEPtr = castPtr

--- We are in a little endian machine.

instance EndianStore (BE Word32) where
  load  ptr    = fmap byteSwap32 <$> peek ptr
  store ptr    = poke ptr . fmap byteSwap32
  adjustEndian = c_Swap32Array . unBEPtr


instance EndianStore (BE Word64) where
  load  ptr    = fmap byteSwap64 <$> peek ptr
  store ptr    = poke ptr . fmap byteSwap64
  adjustEndian = c_Swap64Array . unBEPtr


instance EndianStore (LE Word32) where
  load             = peek
  store            = poke
  adjustEndian _ _ = return ()

instance EndianStore (LE Word64) where
  load              = peek
  store             = poke
  adjustEndian _ _  = return ()


#endif

------------------- Unboxed vector of Endian word types ---------------

instance Unbox w => Unbox (LE w)
instance Unbox w => Unbox (BE w)

------------------- Defining the vector types --------------------------

newtype instance MVector s (LE w) = MV_LE (MVector s w)
newtype instance Vector    (LE w) = V_LE  (Vector w)

newtype instance MVector s (BE w) = MV_BE (MVector s w)
newtype instance Vector    (BE w) = V_BE  (Vector w)

instance Unbox w => GVM.MVector MVector (LE w) where
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicOverlaps #-}
  {-# INLINE basicUnsafeNew #-}
  {-# INLINE basicUnsafeReplicate #-}
  {-# INLINE basicUnsafeRead #-}
  {-# INLINE basicUnsafeWrite #-}
  {-# INLINE basicClear #-}
  {-# INLINE basicSet #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE basicUnsafeGrow #-}
  basicLength          (MV_LE v)        = GVM.basicLength v
  basicUnsafeSlice i n (MV_LE v)        = MV_LE $ GVM.basicUnsafeSlice i n v
  basicOverlaps (MV_LE v1) (MV_LE v2)   = GVM.basicOverlaps v1 v2

  basicUnsafeRead  (MV_LE v) i          = LE <$> GVM.basicUnsafeRead v i
  basicUnsafeWrite (MV_LE v) i (LE x)   = GVM.basicUnsafeWrite v i x

  basicClear (MV_LE v)                  = GVM.basicClear v
  basicSet   (MV_LE v)         (LE x)   = GVM.basicSet v x

  basicUnsafeNew n                      = MV_LE <$> GVM.basicUnsafeNew n
  basicUnsafeReplicate n     (LE x)     = MV_LE <$> GVM.basicUnsafeReplicate n x
  basicUnsafeCopy (MV_LE v1) (MV_LE v2) = GVM.basicUnsafeCopy v1 v2
  basicUnsafeGrow (MV_LE v)   n         = MV_LE <$> GVM.basicUnsafeGrow v n
  basicInitialize (MV_LE v)           = GVM.basicInitialize v

instance Unbox w => GV.Vector Vector (LE w) where
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE elemseq #-}
  basicUnsafeFreeze (MV_LE v)   = V_LE  <$> GV.basicUnsafeFreeze v
  basicUnsafeThaw (V_LE v)      = MV_LE <$> GV.basicUnsafeThaw v
  basicLength (V_LE v)          = GV.basicLength v
  basicUnsafeSlice i n (V_LE v) = V_LE $ GV.basicUnsafeSlice i n v
  basicUnsafeIndexM (V_LE v) i  = LE   <$>  GV.basicUnsafeIndexM v i

  basicUnsafeCopy (MV_LE mv) (V_LE v) = GV.basicUnsafeCopy mv v
  elemseq _ (LE x)                    = GV.elemseq (undefined :: Vector a) x


instance Unbox w => GVM.MVector MVector (BE w) where
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicOverlaps #-}
  {-# INLINE basicUnsafeNew #-}
  {-# INLINE basicUnsafeReplicate #-}
  {-# INLINE basicUnsafeRead #-}
  {-# INLINE basicUnsafeWrite #-}
  {-# INLINE basicClear #-}
  {-# INLINE basicSet #-}
  {-# INLINE basicUnsafeCopy #-}
  {-# INLINE basicUnsafeGrow #-}
  basicLength          (MV_BE v)        = GVM.basicLength v
  basicUnsafeSlice i n (MV_BE v)        = MV_BE $ GVM.basicUnsafeSlice i n v
  basicOverlaps (MV_BE v1) (MV_BE v2)   = GVM.basicOverlaps v1 v2

  basicUnsafeRead  (MV_BE v) i          = BE <$> GVM.basicUnsafeRead v i
  basicUnsafeWrite (MV_BE v) i (BE x)   = GVM.basicUnsafeWrite v i x

  basicClear (MV_BE v)                  = GVM.basicClear v
  basicSet   (MV_BE v)         (BE x)   = GVM.basicSet v x

  basicUnsafeNew n                      = MV_BE <$> GVM.basicUnsafeNew n
  basicUnsafeReplicate n     (BE x)     = MV_BE <$> GVM.basicUnsafeReplicate n x
  basicUnsafeCopy (MV_BE v1) (MV_BE v2) = GVM.basicUnsafeCopy v1 v2
  basicUnsafeGrow (MV_BE v)   n         = MV_BE <$> GVM.basicUnsafeGrow v n
  basicInitialize (MV_BE v)           = GVM.basicInitialize v



instance Unbox w => GV.Vector Vector (BE w) where
  {-# INLINE basicUnsafeFreeze #-}
  {-# INLINE basicUnsafeThaw #-}
  {-# INLINE basicLength #-}
  {-# INLINE basicUnsafeSlice #-}
  {-# INLINE basicUnsafeIndexM #-}
  {-# INLINE elemseq #-}
  basicUnsafeFreeze (MV_BE v)   = V_BE  <$> GV.basicUnsafeFreeze v
  basicUnsafeThaw (V_BE v)      = MV_BE <$> GV.basicUnsafeThaw v
  basicLength (V_BE v)          = GV.basicLength v
  basicUnsafeSlice i n (V_BE v) = V_BE $ GV.basicUnsafeSlice i n v
  basicUnsafeIndexM (V_BE v) i  = BE   <$>  GV.basicUnsafeIndexM v i

  basicUnsafeCopy (MV_BE mv) (V_BE v) = GV.basicUnsafeCopy mv v
  elemseq _ (BE x)                    = GV.elemseq (undefined :: Vector a) x
