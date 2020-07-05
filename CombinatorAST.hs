{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TemplateHaskell #-}
module CombinatorAST where

import Indexed                    (IFunctor, Fix(In), Const1(..), imap, cata)
import Instructions               (IMVar, MVar(..), IΣVar(..))
import Utils                      (WQ, code)
import Language.Haskell.TH.Syntax (Lift)
import Defunc
import Data.List                  (intercalate)

-- Parser wrapper type
newtype Parser a = Parser {unParser :: Fix (Combinator WQ) a}

-- Core smart constructors
{-# INLINE _pure #-}
_pure :: DefuncUser WQ a -> Parser a
_pure = Parser . In . Pure

infixl 4 <*>
(<*>) :: Parser (a -> b) -> Parser a -> Parser b
Parser p <*> Parser q = Parser (In (p :<*>: q))

infixl 4 <*
(<*) :: Parser a -> Parser b -> Parser a
Parser p <* Parser q = Parser (In (p :<*: q))

infixl 4 *>
(*>) :: Parser a -> Parser b -> Parser b
Parser p *> Parser q = Parser (In (p :*>: q))

empty :: Parser a
empty = Parser (In Empty)

infixl 3 <|>
(<|>) :: Parser a -> Parser a -> Parser a
Parser p <|> Parser q = Parser (In (p :<|>: q))

{-# INLINE _satisfy #-}
_satisfy :: DefuncUser WQ (Char -> Bool) -> Parser Char
_satisfy = Parser . In . Satisfy

lookAhead :: Parser a -> Parser a
lookAhead = Parser . In . LookAhead . unParser

notFollowedBy :: Parser a -> Parser ()
notFollowedBy = Parser . In . NotFollowedBy . unParser

try :: Parser a -> Parser a
try = Parser . In . Try . unParser

_conditional :: [(DefuncUser WQ (a -> Bool), Parser b)] -> Parser a -> Parser b -> Parser b
_conditional cs (Parser p) (Parser def) =
  let (fs, qs) = unzip cs
  in Parser (In (Match p fs (map unParser qs) def))

branch :: Parser (Either a b) -> Parser (a -> c) -> Parser (b -> c) -> Parser c
branch (Parser c) (Parser p) (Parser q) = Parser (In (Branch c p q))

chainPre :: Parser (a -> a) -> Parser a -> Parser a
chainPre (Parser op) (Parser p) = Parser (In (ChainPre op p))

chainPost :: Parser a -> Parser (a -> a) -> Parser a
chainPost (Parser p) (Parser op) = Parser (In (ChainPost p op))

debug :: String -> Parser a -> Parser a
debug name (Parser p) = Parser (In (Debug name p))

-- Core datatype
data Combinator (q :: * -> *) (k :: * -> *) (a :: *) where
  Pure           :: DefuncUser q a -> Combinator q k a
  Satisfy        :: DefuncUser q (Char -> Bool) -> Combinator q k Char
  (:<*>:)        :: k (a -> b) -> k a -> Combinator q k b
  (:*>:)         :: k a -> k b -> Combinator q k b
  (:<*:)         :: k a -> k b -> Combinator q k a
  (:<|>:)        :: k a -> k a -> Combinator q k a
  Empty          :: Combinator q k a
  Try            :: k a -> Combinator q k a
  LookAhead      :: k a -> Combinator q k a
  Let            :: Bool -> MVar a -> k a -> Combinator q k a
  NotFollowedBy  :: k a -> Combinator q k ()
  Branch         :: k (Either a b) -> k (a -> c) -> k (b -> c) -> Combinator q k c
  Match          :: k a -> [DefuncUser q (a -> Bool)] -> [k b] -> k b -> Combinator q k b
  ChainPre       :: k (a -> a) -> k a -> Combinator q k a
  ChainPost      :: k a -> k (a -> a) -> Combinator q k a
  Debug          :: String -> k a -> Combinator q k a
  MetaCombinator :: MetaCombinator -> k a -> Combinator q k a

data MetaCombinator where
  Cut         :: MetaCombinator
  RequiresCut :: MetaCombinator

-- Instances
instance IFunctor (Combinator q) where
  imap _ (Pure x)             = Pure x
  imap _ (Satisfy p)          = Satisfy p
  imap f (p :<*>: q)          = f p :<*>: f q
  imap f (p :*>: q)           = f p :*>: f q
  imap f (p :<*: q)           = f p :<*: f q
  imap f (p :<|>: q)          = f p :<|>: f q
  imap _ Empty                = Empty
  imap f (Try p)              = Try (f p)
  imap f (LookAhead p)        = LookAhead (f p)
  imap f (Let r v p)          = Let r v (f p)
  imap f (NotFollowedBy p)    = NotFollowedBy (f p)
  imap f (Branch b p q)       = Branch (f b) (f p) (f q)
  imap f (Match p fs qs d)    = Match (f p) fs (map f qs) (f d)
  imap f (ChainPre op p)      = ChainPre (f op) (f p)
  imap f (ChainPost p op)     = ChainPost (f p) (f op)
  imap f (Debug name p)       = Debug name (f p)
  imap f (MetaCombinator m p) = MetaCombinator m (f p)

instance Show (Fix (Combinator q) a) where
  show = getConst1 . cata (Const1 . alg)
    where
      alg (Pure x)                                  = "(pure " ++ show x ++ ")"
      alg (Satisfy f)                               = "(satisfy " ++ show f ++ ")"
      alg (Const1 pf :<*>: Const1 px)               = concat ["(", pf, " <*> ",  px, ")"]
      alg (Const1 p :*>: Const1 q)                  = concat ["(", p, " *> ", q, ")"]
      alg (Const1 p :<*: Const1 q)                  = concat ["(", p, " <* ", q, ")"]
      alg (Const1 p :<|>: Const1 q)                 = concat ["(", p, " <|> ", q, ")"]
      alg Empty                                     = "empty"
      alg (Try (Const1 p))                          = concat ["(try ", p, ")"]
      alg (LookAhead (Const1 p))                    = concat ["(lookAhead ", p, ")"]
      alg (Let False v _)                           = concat ["(let-bound ", show v, ")"]
      alg (Let True v _)                            = concat ["(rec ", show v, ")"]
      alg (NotFollowedBy (Const1 p))                = concat ["(notFollowedBy ", p, ")"]
      alg (Branch (Const1 b) (Const1 p) (Const1 q)) = concat ["(branch ", b, " ", p, " ", q, ")"]
      alg (Match (Const1 p) fs qs (Const1 def))     = concat ["(match ", p, " ", show fs, " [", intercalate ", " (map getConst1 qs), "] ", def, ")"]
      alg (ChainPre (Const1 op) (Const1 p))         = concat ["(chainPre ", op, " ", p, ")"]
      alg (ChainPost (Const1 p) (Const1 op))        = concat ["(chainPost ", p, " ", op, ")"]
      alg (Debug _ (Const1 p))                      = p
      alg (MetaCombinator m (Const1 p))             = concat [p, " [", show m, "]"]

instance Show MetaCombinator where
  show Cut = "coins after"
  show RequiresCut = "requires cut"