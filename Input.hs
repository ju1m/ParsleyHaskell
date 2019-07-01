{-# LANGUAGE BangPatterns,
             MagicHash,
             UnboxedTuples,
             TemplateHaskell,
             FlexibleInstances,
             TypeApplications,
             MultiParamTypeClasses,
             TypeFamilies,
             PolyKinds,
             DataKinds #-}
module Input where

import Utils                    (TExpQ)
import Data.Array.Base          (UArray(..), listArray)
import GHC.Prim                 (Int#, ByteArray#, indexWideCharArray#, indexWord16Array#, readWord8OffAddr#, word2Int#, chr#, touch#, realWorld#)
import GHC.Exts                 (Int(..), Char(..), TYPE, RuntimeRep(..))
import Data.Text.Array          (aBA)
import Data.Text.Internal       (Text(..))
import Data.ByteString.Internal (ByteString(..))
import GHC.ForeignPtr           (ForeignPtr(..))
import Control.Monad.ST         (ST)
import Data.STRef               (STRef)
import Data.STRef.Unboxed       (STRefU)
import qualified Data.Text as Text (length, index)

data PreparedInput rep = PreparedInput {-next-} (rep -> (# Char, rep #))
                                       {-more-} (rep -> Bool)
                                       {-same-} (rep -> rep -> Bool)
                                       {-box-} rep (Unboxed rep -> rep)
                                       {-unbox-} (rep -> Unboxed rep)
                                       {-newC-} 
                                       {-readC-} 
                                       {-writeC-} 
newtype Text16                            = Text16 Text

data OffString = OffString {-# UNPACK #-} !Int !String

type family Rep rep where
  Rep Int = IntRep
  Rep OffString = LiftedRep

type family Unboxed rep :: TYPE (Rep rep) where
  Unboxed Int = Int#
  Unboxed OffString = OffString

type family CRef s rep where
  CRef s Int = STRefU s Int
  CRef s OffString = STRef s OffString

class Input s rep where
  prepare :: TExpQ s -> TExpQ (PreparedInput rep)

instance Input [Char] Int where 
  prepare input = prepare @(UArray Int Char) [||listArray (0, length $$input-1) $$input||]

instance Input (UArray Int Char) Int where 
  prepare qinput = [||
      let UArray _ _ size input# = $$qinput
          next i@(I# i#) = (# C# (indexWideCharArray# input# i#), i + 1 #)
      in PreparedInput next (< size) (==) 0 (\i# -> I# i#) (\(I# i#) -> i#)
    ||]

instance Input Text16 Int where
  prepare qinput = [||
      let Text16 (Text arr off size) = $$qinput
          arr# = aBA arr
          next i@(I# i#) = (# C# (chr# (word2Int# (indexWord16Array# arr# i#))), i + 1 #)
      in PreparedInput next (< size) (==) off (\i# -> I# i#) (\(I# i#) -> i#)
    ||]

-- I'd *strongly* advise against using this, parsing complexity is O(n^2) for this variant
instance Input Text Int where
  prepare qinput = [||
      let input = $$qinput
          size = Text.length input
          next i = (# Text.index input i, i + 1 #)
      in PreparedInput next (< size) (==) 0 (\i# -> I# i#) (\(I# i#) -> i#)
    ||]

instance Input ByteString Int where
  prepare qinput = [||
      let PS (ForeignPtr addr# final) off size = $$qinput
          next i@(I# i#) = 
            case readWord8OffAddr# addr# i# realWorld# of
              (# s', x #) -> case touch# final s' of 
                _ -> (# C# (chr# (word2Int# x)), i + 1 #)
      in PreparedInput next (< size) (==) off (\i# -> I# i#) (\(I# i#) -> i#)
    ||]

--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \ptr -> peekByteOff ptr (I# (off# +# i#))
--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \ptr -> peek (ptr `plusPtr` (I# (off# +# i#)))
--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \ptr -> peekElemOff ptr (I# (off# +# i#))
--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \ptr -> readWord8OffPtr ptr (I# (off# +# i#))
--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \Ptr addr# -> readWord8OffPtr (Ptr (addr#)) (I# (off# +# i#))
--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \Ptr addr# -> 
--  IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', W8# x #)
--accursedUnutterablePerformIO $ withForeignPtr (ForeignPtr addr# final) $ \Ptr addr# -> 
--  IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     touchForeignPtr (ForeignPtr addr# final)
--     return r
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     touch final
--     return r
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     IO $ \s -> case touch# final s of s' -> (# s', () #)
--     IO $ \s -> (# s, r #)
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     (IO $ \s -> case touch# final s of s' -> (# s', () #)) >> (IO $ \s -> (# s, r #))
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     IO $ \s -> case (\s -> case touch# final s of s' -> (# s', () #)) s of (# s', _ #) -> (\s -> (# s, r #)) s'
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     IO $ \s -> case (\s -> case touch# final s of s' -> (# s', () #)) s of (# s', _ #) -> (# s', r #)
--accursedUnutterablePerformIO $ 
--  do r <- IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)
--     IO $ \s -> case touch# final s of s' -> (# s', r #)
--accursedUnutterablePerformIO $ 
--  (IO $ \s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)) 
--    >>= (\r -> IO $ \s -> case touch# final s of s' -> (# s', r #)) 
--accursedUnutterablePerformIO $ 
--  IO $ \s -> 
--    case (\s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)) s of
--      (# s', x #) -> (\r s -> case touch# final s of s' -> (# s', r #)) x s'
--accursedUnutterablePerformIO $ 
--  IO $ \s -> 
--    case (\s -> case readWord8OffAddr# addr# (off# +# i#) s of (# s', x #) -> (# s', C# (chr# (word2Int# x)) #)) s of
--      (# s', x #) -> case touch# final s' of s'' -> (# s'', x #)
--accursedUnutterablePerformIO $ 
--  IO $ \s -> 
--    case readWord8OffAddr# addr# (off# +# i#) s of
--      (# s', x #) -> case touch# final s' of 
--        s'' -> (# s'', C# (chr# (word2Int# x)) #)
-- case (\s -> 
--   case readWord8OffAddr# addr# (off# +# i#) s of
--     (# s', x #) -> case touch# final s' of 
--       s'' -> (# s'', C# (chr# (word2Int# x)) #)) realWorld# of (# _, r #) -> r
-- case readWord8OffAddr# addr# (off# +# i#) realWorld# of
--   (# s', x #) -> case touch# final s' of 
--     _ -> C# (chr# (word2Int# x))