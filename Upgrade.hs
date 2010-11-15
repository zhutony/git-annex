{- git-annex upgrade support
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Upgrade where

import System.Directory
import Control.Monad.State (liftIO)
import System.Posix.Files

import Core
import Types
import Locations
import qualified GitRepo as Git
import qualified Annex
import qualified Backend
import Messages
import Version

{- Uses the annex.version git config setting to automate upgrades. -}
upgrade :: Annex Bool
upgrade = do
	version <- getVersion
	case version of
		Just "0" -> upgradeFrom0
		Nothing -> return True -- repo not initted yet, no version
		Just v | v == currentVersion -> return True
		Just _ -> error "this version of git-annex is too old for this git repository!"

upgradeFrom0 :: Annex Bool
upgradeFrom0 = do
	showSideAction "Upgrading object directory layout..."
	g <- Annex.gitRepo

	-- do the reorganisation of the files
	let olddir = annexDir g
	keys <- getKeysPresent' olddir
	_ <- mapM (\k -> moveAnnex k $ olddir ++ "/" ++ keyFile k) keys

	-- update the symlinks to the files
	files <- liftIO $ Git.inRepo g $ Git.workTree g
	fixlinks files
	Annex.queueRun

	setVersion

	return True

	where
		fixlinks [] = return ()
		fixlinks (f:fs) = do
			r <- Backend.lookupFile f
			case r of
				Nothing -> return ()
				Just (k, _) -> do
					link <- calcGitLink f k
					liftIO $ removeFile f
					liftIO $ createSymbolicLink link f
					Annex.queue "add" ["--"] f
			fixlinks fs