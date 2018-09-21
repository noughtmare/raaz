{-# LANGUAGE CPP #-}
module Raaz.Entropy( getEntropy, entropySource ) where

#include <Windows.h>
#include <Wincrypt.h>

##if defined(i386_HOST_ARCH)
## define WINDOWS_CCONV stdcall
##elif defined(x86_64_HOST_ARCH)
## define WINDOWS_CCONV ccall
##else
## error Unknown mingw32 arch
##endif

import Control.Monad.IO.Class( MonadIO, liftIO)
import Control.Monad (when)
import Data.Bits ((.|.))
import Data.Word (Word8(), Word32())
import Foreign.Ptr (Ptr(), nullPtr, castPtr)
import Foreign.Storable (peek)
import Foreign.C.String (CWString())
import Raaz.Core
import Raaz.Core.Types.Internal

type HCRYPTPROV = Ptr ()

-- | The name of the source from which entropy is gathered. For
-- information purposes only.
entropySource :: String
entropySource = "CryptGenRandom(windows)"

foreign import WINDOWS_CCONV unsafe "Wincrypt.h CryptGenRandom"
    c_CryptGenRandom :: HCRYPTPROV -> Word32 -> Ptr Word8 -> IO Bool

foreign import WINDOWS_CCONV unsafe "Wincrypt.h CryptAcquireContextW"
    c_CryptAcquireContext :: Ptr HCRYPTPROV -> CWString -> CWString
                          -> Word32 -> Word32 -> IO Bool

foreign import WINDOWS_CCONV unsafe "Wincrypt.h CryptReleaseContext"
    c_CryptReleaseContext :: HCRYPTPROV -> Word32 -> IO Bool

-- | Get cryptographically random bytes from the system.
getEntropy :: (MonadIO m, LengthUnit l) => l -> Pointer -> m (BYTES Int)
getEntropy l ptr = liftIO $ allocaBuffer ptrSize $ \ctx ->
    do let addr = castPtr ctx
       ctx_ok <- c_CryptAcquireContext addr nullPtr nullPtr
                       (#const PROV_RSA_FULL)
                       ((#const CRYPT_VERIFYCONTEXT) .|. (#const CRYPT_SILENT))
       when (not ctx_ok) $ fail "Call to CryptAcquireContext failed."
       ctx'    <- peek addr
       success <- c_CryptGenRandom ctx' (fromIntegral bytes) (castPtr ptr)
       _ <- c_CryptReleaseContext ctx' 0
       if success
          then return $ BYTES bytes
          else fail "Unable to generate entropy. Call to CryptGenRandom failed."
  where BYTES bytes = inBytes l
        ptrSize = BYTES ((#size HCRYPTPROV) :: Int)
