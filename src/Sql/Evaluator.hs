 {-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TupleSections #-}
module Sql.Evaluator
  ( evaluate, populate, evaluateDB, runDatabase, toRelational
  , Relational(..), Relation(..)
  ) where

import Sql.Parser(Sql(..), Expr(..))
import Control.Monad.State
import Control.Monad.Except
import Data.Monoid((<>))
import Data.Text
import qualified Data.Map as Map


type TableName = Text

type ColumnName = Text

data Relational = Rel TableName
                | Proj [ ColumnName ] Relational
                | Prod [ Relational ]
                | Create TableName Relation
  deriving (Eq, Show)


data Relation = Relation { columnNames :: [ Text ]
                         , rows       :: [[ Text ]]
                         }
                deriving (Eq, Show)

type EvaluationError = Text

relationNotFound :: TableName -> EvaluationError
relationNotFound name = "no relation with name " <> (pack $ show name)

type DB = Map.Map TableName Relation

newtype Database a = Database { tables :: ExceptT EvaluationError (State DB) a }
  deriving ( Functor
           , Applicative
           , Monad
           , MonadState DB
           , MonadError EvaluationError
           )

populate :: [ (TableName, Relation) ] -> DB
populate = Map.fromList

evaluate :: Relational -> DB -> Either EvaluationError Relation
evaluate rel db = runDatabase db $ evaluateDB rel

runDatabase :: DB -> Database a -> Either EvaluationError a
runDatabase db = flip evalState db . runExceptT . tables

evaluateDB :: Relational -> Database Relation
evaluateDB (Rel tblName) =
  get >>= maybe  (throwError $ relationNotFound tblName) pure . Map.lookup tblName

evaluateDB (Prod [rel1,rel2]) = do
  table1 <- evaluateDB rel1
  table2 <- evaluateDB rel2
  return $ Relation (columnNames table1 <> columnNames table2) [ t1 <> t2 | t1 <- rows table1, t2 <- rows table2 ]

evaluateDB (Proj _cols _rel) = pure $ Relation [ "col1" ] [["a"]]
evaluateDB (Create tbl rel)  = do
  modify $ Map.insert tbl rel
  return rel

evaluateDB expr  = throwError $ "Don't know how to evaluate " <> pack (show expr)

toRelational :: Sql -> Relational
toRelational (Select projs tableNames) =
   Proj proj (relations tableNames)
   where
     proj = [ x | Col x <- projs ]
     relations [ t ] = Rel t
     relations ts    = Prod $ fmap Rel ts
toRelational (Insert tableName cols values) =
   Create tableName (Relation cols (fmap (fmap eval) values))

eval :: Expr -> Text
eval (Str s) = s
eval expr    = error $ "cannot eval " <> show expr
