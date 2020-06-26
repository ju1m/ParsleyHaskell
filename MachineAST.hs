{-# LANGUAGE GADTs,
             DataKinds,
             TypeOperators,
             FlexibleInstances,
             TemplateHaskell,
             PolyKinds,
             KindSignatures,
             ScopedTypeVariables,
             GeneralizedNewtypeDeriving,
             PatternSynonyms,
             StandaloneDeriving #-}
module MachineAST where

import Indexed           (IFunctor4, Fix4(In4), Const4(..), imap4, cata4, Nat(..))
import Utils             (WQ(..))
import Defunc            (Defunc(APP), pattern FLIP_H)
import Data.Word         (Word64)
import Safe.Coerce       (coerce)
import Data.List         (intercalate)
import Data.GADT.Compare (GEq, GCompare, gcompare, geq, (:~:)(Refl), GOrdering(..))

type One = Succ Zero
newtype Machine o a = Machine { getMachine :: Fix4 (M WQ o) '[] One a a }
newtype ΣVar (a :: *) = ΣVar IΣVar
newtype MVar (a :: *) = MVar IMVar
newtype ΦVar (a :: *) = ΦVar IΦVar
newtype IMVar = IMVar Word64 deriving (Ord, Eq, Num, Enum, Show)
newtype IΦVar = IΦVar Word64 deriving (Ord, Eq, Num, Enum, Show)
newtype IΣVar = IΣVar Word64 deriving (Ord, Eq, Num, Enum, Show)
newtype LetBinding q o a x = LetBinding (Fix4 (M q o) '[] One x a)
instance Show (LetBinding q o a x) where show (LetBinding m) = show m

data M q o (k :: [*] -> Nat -> * -> * -> *) (xs :: [*]) (n :: Nat) (r :: *) (a :: *) where
  Ret       :: M q o k '[x] n x a
  Push      :: Defunc q x -> k (x : xs) n r a -> M q o k xs n r a
  Pop       :: k xs n r a -> M q o k (x : xs) n r a
  Lift2     :: Defunc q (x -> y -> z) -> k (z : xs) n r a -> M q o k (y : x : xs) n r a
  Sat       :: Defunc q (Char -> Bool) -> k (Char : xs) (Succ n) r a -> M q o k xs (Succ n) r a
  Call      :: MVar x -> k (x : xs) (Succ n) r a -> M q o k xs (Succ n) r a
  Jump      :: MVar x -> M q o k '[] (Succ n) x a
  Empt      :: M q o k xs (Succ n) r a
  Commit    :: k xs n r a -> M q o k xs (Succ n) r a
  Catch     :: k xs (Succ n) r a -> k (o : xs) n r a -> M q o k xs n r a
  Handler   :: Handler o k xs n r a -> M q o k (o : xs) n r a
  Tell      :: k (o : xs) n r a -> M q o k xs n r a
  Seek      :: k xs n r a -> M q o k (o : xs) n r a
  Case      :: k (x : xs) n r a -> k (y : xs) n r a -> M q o k (Either x y : xs) n r a
  Choices   :: [Defunc q (x -> Bool)] -> [k xs n r a] -> k xs n r a -> M q o k (x : xs) n r a
  ChainIter :: ΣVar x -> MVar x -> M q o k '[] (Succ n) x a
  ChainInit :: ΣVar x -> k '[] (Succ n) x a -> MVar x -> k xs n r a -> M q o k xs n r a
  Join      :: ΦVar x -> M q o k (x : xs) n r a
  MkJoin    :: ΦVar x -> k (x : xs) n r a -> k xs n r a -> M q o k xs n r a
  Swap      :: k (x : y : xs) n r a -> M q o k (y : x : xs) n r a
  Make      :: ΣVar x -> k xs n r a -> M q o k (x : xs) n r a
  Get       :: ΣVar x -> k (x : xs) n r a -> M q o k xs n r a
  Put       :: ΣVar x -> k xs n r a -> M q o k (x : xs) n r a
  LogEnter  :: String -> k xs n r a -> M q o k xs n r a
  LogExit   :: String -> k xs n r a -> M q o k xs n r a
  MetaM     :: MetaM -> k xs n r a -> M q o k xs n r a

data Handler o (k :: [*] -> Nat -> * -> * -> *) (xs :: [*]) (n :: Nat) (r :: *) (a :: *) where
  Parsec :: k xs n r a -> Handler o k xs n r a
  Log :: String -> Handler o k xs n r a
deriving instance Show (Handler o (Const4 String) xs n r a)

data MetaM where
  AddCoins    :: Int -> MetaM
  FreeCoins   :: Int -> MetaM
  RefundCoins :: Int -> MetaM
  DrainCoins  :: Int -> MetaM

mkCoin :: (Int -> MetaM) -> Int -> Fix4 (M q o) xs n r a -> Fix4 (M q o) xs n r a
mkCoin meta 0 = id
mkCoin meta n = In4 . MetaM (meta n)

addCoins = mkCoin AddCoins
freeCoins = mkCoin FreeCoins
refundCoins = mkCoin RefundCoins
drainCoins = mkCoin DrainCoins

_App :: Fix4 (M q o) (y : xs) n r a -> M q o (Fix4 (M q o)) (x : (x -> y) : xs) n r a
_App m = Lift2 APP m

_Fmap :: Defunc q (x -> y) -> Fix4 (M q o) (y : xs) n r a -> M q o (Fix4 (M q o)) (x : xs) n r a
_Fmap f m = Push f (In4 (Lift2 (FLIP_H APP) m))

_Modify :: ΣVar x -> Fix4 (M q o) xs n r a -> M q o (Fix4 (M q o)) ((x -> x) : xs) n r a
_Modify σ m = Get σ (In4 (_App (In4 (Put σ m))))

instance IFunctor4 (M q o) where
  imap4 f Ret                 = Ret
  imap4 f (Push x k)          = Push x (f k)
  imap4 f (Pop k)             = Pop (f k)
  imap4 f (Lift2 g k)         = Lift2 g (f k)
  imap4 f (Sat g k)           = Sat g (f k)
  imap4 f (Call μ k)          = Call μ (f k)
  imap4 f (Jump μ)            = Jump μ
  imap4 f Empt                = Empt
  imap4 f (Commit k)          = Commit (f k)
  imap4 f (Catch p h)         = Catch (f p) (f h)
  imap4 f (Handler h)         = Handler (imap4 f h)
  imap4 f (Tell k)            = Tell (f k)
  imap4 f (Seek k)            = Seek (f k)
  imap4 f (Case p q)          = Case (f p) (f q)
  imap4 f (Choices fs ks def) = Choices fs (map f ks) (f def)
  imap4 f (ChainIter σ μ)     = ChainIter σ μ
  imap4 f (ChainInit σ l μ k) = ChainInit σ (f l) μ (f k)
  imap4 f (Join φ)            = Join φ
  imap4 f (MkJoin φ p k)      = MkJoin φ (f p) (f k)
  imap4 f (Swap k)            = Swap (f k)
  imap4 f (Make σ k)          = Make σ (f k)
  imap4 f (Get σ k)           = Get σ (f k)
  imap4 f (Put σ k)           = Put σ (f k)
  imap4 f (LogEnter name k)   = LogEnter name (f k)
  imap4 f (LogExit name k)    = LogExit name (f k)
  imap4 f (MetaM m k)         = MetaM m (f k)

instance IFunctor4 (Handler o) where
  imap4 f (Parsec k) = Parsec (f k)
  imap4 f (Log msg) = Log msg

instance Show (Machine o a) where show = show . getMachine
instance Show (Fix4 (M q o) xs n r a) where
  show x = let Const4 s = cata4 alg x in s where
    alg :: forall i j k. M q o (Const4 String) i j k a -> Const4 String i j k a
    alg Ret                 = Const4 $ "Ret"
    alg (Call μ k)          = Const4 $ "(Call " ++ show μ ++ " " ++ show k ++ ")"
    alg (Jump μ)            = Const4 $ "(Jump " ++ show μ ++ ")"
    alg (Push x k)          = Const4 $ "(Push " ++ show x ++ " " ++ show k ++ ")"
    alg (Pop k)             = Const4 $ "(Pop " ++ show k ++ ")"
    alg (Lift2 f k)         = Const4 $ "(Lift2 " ++ show f ++ " " ++ show k ++ ")"
    alg (Sat f k)           = Const4 $ "(Sat " ++ show f ++ " " ++ show k ++ ")"
    alg Empt                = Const4 $ "Empt"
    alg (Commit k)          = Const4 $ "(Commit " ++ show k ++ ")"
    alg (Catch p h)         = Const4 $ "(Catch " ++ show p ++ " " ++ show h ++ ")"
    alg (Handler h)         = Const4 $ "(Handler " ++ show h ++ ")"
    alg (Tell k)            = Const4 $ "(Tell " ++ show k ++ ")"
    alg (Seek k)            = Const4 $ "(Seek " ++ show k ++ ")"
    alg (Case p q)          = Const4 $ "(Case " ++ show p ++ " " ++ show q ++ ")"
    alg (Choices fs ks def) = Const4 $ "(Choices " ++ show fs ++ " [" ++ intercalate ", " (map show ks) ++ "] " ++ show def ++ ")"
    alg (ChainIter σ μ)     = Const4 $ "(ChainIter " ++ show σ ++ " " ++ show μ ++ ")"
    alg (ChainInit σ m μ k) = Const4 $ "{ChainInit " ++ show σ ++ " " ++ show μ ++ " " ++ show m ++ " " ++ show k ++ "}"
    alg (Join φ)            = Const4 $ show φ
    alg (MkJoin φ p k)      = Const4 $ "(let " ++ show φ ++ " = " ++ show p ++ " in " ++ show k ++ ")"
    alg (Swap k)            = Const4 $ "(Swap " ++ show k ++ ")"
    alg (Make σ k)          = Const4 $ "(Make " ++ show σ ++ " " ++ show k ++ ")"
    alg (Get σ k)           = Const4 $ "(Get " ++ show σ ++ " " ++ show k ++ ")"
    alg (Put σ k)           = Const4 $ "(Put " ++ show σ ++ " " ++ show k ++ ")"
    alg (LogEnter _ k)      = Const4 $ show k
    alg (LogExit _ k)       = Const4 $ show k
    alg (MetaM m k)         = Const4 $ "[" ++ show m ++ "] " ++ show k

instance Show (Const4 String xs n r a) where show = getConst4

instance Show (MVar a) where show (MVar (IMVar μ)) = "μ" ++ show μ
instance Show (ΦVar a) where show (ΦVar (IΦVar φ)) = "φ" ++ show φ
instance Show (ΣVar a) where show (ΣVar (IΣVar σ)) = "σ" ++ show σ

instance Show MetaM where
  show (AddCoins n)    = "Add " ++ show n ++ " coins"
  show (RefundCoins n) = "Refund " ++ show n ++ " coins"
  show (DrainCoins n)    = "Using " ++ show n ++ " coins"

instance GEq ΣVar where
  geq (ΣVar u) (ΣVar v)
    | u == v    = Just (coerce Refl)
    | otherwise = Nothing

instance GCompare ΣVar where
  gcompare (ΣVar u) (ΣVar v) = case compare u v of
    LT -> coerce GLT
    EQ -> coerce GEQ
    GT -> coerce GGT

instance GEq ΦVar where
  geq (ΦVar u) (ΦVar v)
    | u == v    = Just (coerce Refl)
    | otherwise = Nothing

instance GCompare ΦVar where
  gcompare (ΦVar u) (ΦVar v) = case compare u v of
    LT -> coerce GLT
    EQ -> coerce GEQ
    GT -> coerce GGT

instance GEq MVar where
  geq (MVar u) (MVar v)
    | u == v    = Just (coerce Refl)
    | otherwise = Nothing

instance GCompare MVar where
  gcompare (MVar u) (MVar v) = case compare u v of
    LT -> coerce GLT
    EQ -> coerce GEQ
    GT -> coerce GGT