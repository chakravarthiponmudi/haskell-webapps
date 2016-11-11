{-# LANGUAGE DeriveFoldable, LambdaCase, GADTs #-}

module  Types.DB
        ( HasTableName(..)
        , DBResult(..)
        , TimestampedUpdate
        , DBWriteResult
        , DBUniqueResult
        , DBConnector(..)
        , dbWriteResult
        , dbUniqueResult
        , module DataSource
        ) where


import  DataSource                  (HasPKey, PKey, mkDBErr)

import  Data.Time.LocalTime         (ZonedTime)
import  Database.HDBC               (SqlError, IConnection)
import  Database.Relational.Query   (Update)


class HasTableName a where
    getTableName :: a -> String

-- a database connector that can carry tenant and/or user identity with it
data DBConnector where
    DBConnector :: IConnection conn =>
        { dbTenantId    :: Maybe PKey
        , dbUserId      :: Maybe PKey
        , dbConn        :: conn
        } -> DBConnector


data DBResult a
    = ResEmpty
    | ResJust   a
    | ResMany   [a]
    | ResPKId   PKey
    | ResDBErr  SqlError
    deriving (Show, Eq, Foldable)

type DBWriteResult  = Either SqlError PKey

type DBUniqueResult = Either SqlError

dbWriteResult :: DBResult a -> DBWriteResult
dbWriteResult = \case
    ResPKId k       -> Right k
    ResDBErr err    -> Left err
    _               -> Left $ mkDBErr "expected primary key result"

dbUniqueResult :: DBResult a -> Either SqlError a
dbUniqueResult = \case
    ResJust v       -> Right v
    ResDBErr err    -> Left err
    _               -> Left $ mkDBErr "expected exactly one query result"


type TimestampedUpdate a b = Update ((a, ZonedTime), b)