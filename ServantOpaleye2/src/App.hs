{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE OverloadedStrings   #-}

module App where

import           AppCore
import           AppM
import           Control.Exception          (SomeException)
import           Control.Exception.Lifted   (handle)
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.Trans.Either
import           Control.Monad.Trans.Except
import           Control.Monad.Writer
import           Data.Aeson
import           Data.Text.Lazy             (pack)
import           Data.Text.Lazy.Encoding
import           Database.PostgreSQL.Simple hiding ((:.))
import           GHC.Generics
import           Network.Wai
import           Network.Wai.Handler.Warp
import           Servant
import           System.IO
import           TenantApi

import qualified Endpoints.Authentication as AuthenticationEp
import qualified Endpoints.Tenant as TenantEp

connectDb :: IO Connection
connectDb = connect defaultConnectInfo { connectDatabase = "haskell-webapps" }

-- * api

type TenantApi = AuthenticationEp.Type :<|> TenantEp.Type


tenantApi :: Proxy TenantApi
tenantApi = Proxy

-- * app

authCheck :: BasicAuthCheck String
authCheck =
  let check (BasicAuthData username password) =
        return (Authorized "servant")
  in BasicAuthCheck check

basicAuthServerContext :: Context (BasicAuthCheck String ': '[])
basicAuthServerContext = authCheck :. EmptyContext

run :: IO ()
run = do
  let port = 3000
      settings =
        setPort port $
        setBeforeMainLoop (hPutStrLn stderr ("listening on port " ++ show port)) $
        defaultSettings
  conn <- connectDb
  runSettings settings =<< (mkApp conn)

mkApp :: Connection -> IO Application
mkApp conn = return $ serveWithContext 
                            tenantApi
                            basicAuthServerContext 
                            (server conn)

server :: Connection -> Server TenantApi
server conn = enter (appmToServantM conn) appMServerT

appMServerT::ServerT TenantApi AppM
appMServerT = AuthenticationEp.server :<|> TenantEp.server

runAppM :: AppM a -> Connection -> IO (Either SomeException (a, String))
runAppM x conn = do
  user <- getTestUser
  runExceptT $ handle throwE $ runReaderT (runWriterT x) (conn, Just $ getTestTenant, Just $ user)

appmToServantM :: Connection -> (AppM  :~> ExceptT ServantErr IO)
appmToServantM conn = Nat (appmToServantM' conn)

appmToServantM' :: forall a. Connection -> AppM a  -> ExceptT ServantErr IO a
appmToServantM' conn appm = do
  r <- liftIO $ runAppM appm conn
  case r of
    Right (a, log) -> return a
    Left exp -> throwError err500 { errBody = encodeUtf8.pack $ show exp}