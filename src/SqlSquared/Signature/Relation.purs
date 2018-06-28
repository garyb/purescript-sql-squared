module SqlSquared.Signature.Relation where

import Prelude

import Control.Monad.Gen as Gen
import Control.Monad.Gen.Common as GenC
import Control.Monad.Rec.Class (class MonadRec)
import Data.Foldable as F
import Data.Maybe (Maybe)
import Data.NonEmpty ((:|))
import Data.String.Gen as GenS
import Data.Traversable as T
import Matryoshka (Algebra, CoalgebraM)
import SqlSquared.Path as Pt
import SqlSquared.Signature.Ident as ID
import SqlSquared.Signature.JoinType as JT
import SqlSquared.Utils ((∘))
type JoinRelR a =
  { left ∷ Relation a
  , right ∷ Relation a
  , joinType ∷ JT.JoinType
  , clause ∷ a
  }

type ExprRelR a =
  { expr ∷ a
  , aliasName ∷ String
  }

type VariRelR =
  { vari ∷ String
  , alias ∷ Maybe String
  }

type TableRelR =
  { path ∷ Pt.AnyFile
  , alias ∷ Maybe String
  }

data Relation a
  = JoinRelation (JoinRelR a)
  | ExprRelation (ExprRelR a)
  | VariRelation VariRelR
  | TableRelation TableRelR

derive instance functorRelation ∷ Functor Relation
derive instance eqRelation ∷ Eq a ⇒ Eq (Relation a)
derive instance ordRelation ∷ Ord a ⇒ Ord (Relation a)
instance foldableRelation ∷ F.Foldable Relation where
  foldMap f = case _ of
    JoinRelation { left, right, clause } → F.foldMap f left <> F.foldMap f right <> f clause
    ExprRelation { expr } → f expr
    _ → mempty
  foldl f a = case _ of
    JoinRelation { left, right, clause } →
      f (F.foldl f (F.foldl f a left) right) clause
    ExprRelation { expr } →
      f a expr
    _ → a
  foldr f a = case _ of
    JoinRelation { left, right, clause } →
      F.foldr f (F.foldr f (f clause a) right) left
    ExprRelation { expr } →
      f expr a
    _ → a
instance traversableRelation ∷ T.Traversable Relation where
  traverse f = case _ of
    JoinRelation { left, right, clause, joinType } →
      map JoinRelation
      $ { joinType, left: _, right: _, clause: _}
      <$> T.traverse f left
      <*> T.traverse f right
      <*> f clause
    ExprRelation  { expr, aliasName} →
      (ExprRelation ∘ { expr: _, aliasName})
      <$> f expr
    VariRelation v → pure $ VariRelation v
    TableRelation i → pure $ TableRelation i
  sequence = T.sequenceDefault

printRelation ∷ Algebra Relation String
printRelation = case _ of
  ExprRelation {expr, aliasName} →
    "(" <> expr <> ") AS " <> ID.printIdent aliasName
  VariRelation { vari, alias} →
    ":" <> ID.printIdent vari <> F.foldMap (\a → " AS " <> ID.printIdent a) alias
  TableRelation { path, alias } →
    "`"
    <> Pt.printAnyFilePath path
    <> "`"
    <> F.foldMap (\x → " AS " <> ID.printIdent x) alias
  JoinRelation { left, right, joinType, clause } →
    printRelation left
    <> " "
    <> JT.printJoinType joinType
    <> " "
    <> printRelation right
    <> " ON "
    <> clause

genRelation ∷ ∀ m. Gen.MonadGen m ⇒ MonadRec m ⇒ CoalgebraM m Relation Int
genRelation n =
  if n < 1
  then
    Gen.oneOf $ genTable :|
      [ genVari
      ]
  else
    Gen.oneOf $ genTable :|
      [ genVari
      , genJoin
      , genExpr
      ]
  where
  genVari = do
    vari ← GenS.genUnicodeString
    alias ← GenC.genMaybe GenS.genUnicodeString
    pure $ VariRelation { vari, alias }
  genTable = do
    path ← Pt.genAnyFilePath
    alias ← GenC.genMaybe GenS.genUnicodeString
    pure $ TableRelation { path, alias }
  genExpr = do
    aliasName ← GenS.genUnicodeString
    pure $ ExprRelation { aliasName, expr: n - 1 }
  genJoin = do
    joinType ← JT.genJoinType
    left ← genRelation $ n - 1
    right ← genRelation $ n - 1
    pure $ JoinRelation { joinType, left, right, clause: n - 1 }
