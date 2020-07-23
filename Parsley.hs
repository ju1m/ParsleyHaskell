module Parsley (
    module Parsley,
    module Core,
    module Primitives,
    module Applicative,
    module Alternative,
    module Selective,
    module Combinator,
    module Fold,
    module THUtils,
  ) where

import Prelude hiding      (readFile)
import Data.Text.IO        (readFile)
import Language.Haskell.TH (Q, Dec, Type)
import Parsley.Backend     (codeGen, Input, staticLink, prepare, dynamicLink, InputPolymorphic(..))
import Parsley.Frontend    (compile)

import Parsley.Alternative     as Alternative
import Parsley.Applicative     as Applicative
import Parsley.Core            as Core
import Parsley.Combinator      as Combinator  (item, char, string, satisfy, notFollowedBy, lookAhead, try)
import Parsley.Common.Utils    as THUtils     (code, Quapplicative(..), WQ, Code)
import Parsley.Fold            as Fold        (many, some)
import Parsley.Selective       as Selective
import Parsley.Core.Primitives as Primitives  (debug)

runParser :: Input input => Parser a -> Code (input -> Maybe a)
runParser p = [||\input -> $$(staticLink (compile p codeGen) (prepare [||input||]))||]

buildLoadableParser :: String -> Q Type -> Parser a -> Q [Dec]
buildLoadableParser name tyX p = dynamicLink name tyX (InputPolymorphic (compile p codeGen))

parseFromFile :: Parser a -> Code (FilePath -> IO (Maybe a))
parseFromFile p = [||\filename -> do input <- readFile filename; return ($$(runParser p) (Text16 input))||]
