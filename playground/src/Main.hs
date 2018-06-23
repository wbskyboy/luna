{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE UndecidableInstances #-}

module Main where

import Prologue

import qualified Control.Monad.State                 as State
import qualified Control.Monad.State.Layered         as State
import qualified Control.Concurrent.Async            as Async
import qualified Data.Graph.Data.Graph.Class         as Graph
import qualified  Data.Graph.Data.Component.Vector   as ComponentVector
import qualified Data.List                           as List
import qualified Data.Map                            as Map
import qualified Data.Set                            as Set
import qualified Data.Tag                            as Tag
import qualified Data.Text                           as Text
import qualified Luna.Debug.IR.Visualizer            as Vis
import qualified Luna.IR                             as IR
import qualified Luna.IR.Aliases                     as Uni
import qualified Luna.IR.Layer                       as Layer
import qualified Luna.Pass                           as Pass
import qualified Luna.Pass.Attr                      as Attr
import qualified Luna.Pass.Basic                     as Pass
import qualified Luna.Pass.Scheduler                 as Scheduler
import qualified Luna.Shell                          as Shell
import qualified Luna.Syntax.Text.Parser.Data.Result as Parser
import qualified Luna.Syntax.Text.Parser.Pass        as Parser
import qualified Luna.Syntax.Text.Source             as Parser
import qualified OCI.Pass.Definition.Interface       as Pass
import qualified System.Environment                  as System
import qualified Text.PrettyPrint.ANSI.Leijen        as Doc
import qualified Data.Graph.Data.Layer.Layout    as Layout

import Data.Map  (Map)
import Data.Set  (Set)
import Luna.Pass (Pass)

import Data.Graph.Data.Component.Class (unsafeNull)

import Luna.Syntax.Text.Parser.Data.CodeSpan (CodeSpan)
import Luna.Syntax.Text.Parser.Data.Invalid (Invalids)

import qualified Data.Graph.Data.Graph.Class          as Graph
import Data.Graph.Component.Node.Destruction

import qualified Luna.Pass.Preprocess.PreprocessDef as PreprocessDef
import qualified Luna.Pass.Resolve.Data.Resolution  as Res
import Luna.Pass.Resolve.AliasAnalysis
import Luna.Pass.Data.Root
import Luna.Pass.Data.UniqueNameGen

import qualified Luna.Pass.Sourcing.UnitLoader as ModLoader
import qualified Luna.Pass.Sourcing.Data.Unit  as Unit
import qualified Luna.Pass.Sourcing.Data.Def   as Def
import qualified Luna.Pass.Sourcing.Data.Class as Class
import qualified Luna.Pass.Sourcing.UnitMapper as UnitMap
import qualified Luna.Project as Project
import qualified Data.Bimap as Bimap
import qualified Path as Path
----------------------
-- === TestPass === --
----------------------

-- === Definition === --

data TestPass = TestPass

type instance Pass.Spec TestPass t = TestPassSpec t
type family TestPassSpec t where
    TestPassSpec (Pass.In Pass.Attrs) = '[Root]
    TestPassSpec (Pass.Out Pass.Attrs) = '[ModuleMap]
    TestPassSpec t = Pass.BasicPassSpec t

data VisPass = VisPass

type instance Pass.Spec VisPass t = VisPassSpec t
type family VisPassSpec t where
    VisPassSpec (Pass.In Pass.Attrs) = '[Root, VisName]
    VisPassSpec t = Pass.BasicPassSpec t

data ModuleMap = ModuleMap
    { _functions :: Map.Map IR.Name (IR.Term IR.Function)
    , _classes   :: Map.Map IR.Name (IR.Term IR.Record)
    } deriving (Show)
type instance Attr.Type ModuleMap = Attr.Atomic
instance Default ModuleMap where
    def = ModuleMap def def


-- === Attrs === --

newtype VisName = VisName String
type instance Attr.Type VisName = Attr.Atomic
instance Default VisName where
    def = VisName ""

newtype World = World (IR.Term IR.Unit)
type instance Attr.Type World = Attr.Atomic
instance Default World where
    def = World unsafeNull

instance Pass.Interface TestPass (Pass stage TestPass)
      => Pass.Definition stage TestPass where
    definition = do
        Root root <- Attr.get
        print root
        u@(IR.Unit imphub units cls) <- IR.model (Layout.unsafeRelayout root :: IR.Term IR.Unit)
        clas <- IR.source cls
        Layer.read @IR.Model clas >>= \case
            Uni.Record isNative name params conss decls' -> do
                decls <- traverse IR.source =<< ComponentVector.toList decls'
                ds <- for decls $ \d -> Layer.read @IR.Model d >>= \case
                    Uni.Function nvar' _ _ -> do
                        nvar :: IR.Term IR.Var <- Layout.unsafeRelayout <$> IR.source nvar'
                        (IR.Var n) <- IR.model nvar
                        return $ Just (n, Layout.unsafeRelayout d)
                    _ -> return Nothing
                Attr.put $ ModuleMap (Map.fromList $ catMaybes ds) def


instance Pass.Interface VisPass (Pass stage VisPass)
      => Pass.Definition stage VisPass where
    definition = do
        Root root <- Attr.get
        VisName n <- Attr.get
        print root
        Vis.displayVisualization n root



data ShellCompiler

type instance Graph.Components      ShellCompiler          = '[IR.Terms, IR.Links]
type instance Graph.ComponentLayers ShellCompiler IR.Links = '[IR.Target, IR.Source]
type instance Graph.ComponentLayers ShellCompiler IR.Terms
   = '[IR.Users, IR.Model, IR.Type, CodeSpan]


makeLenses ''ModuleMap
---------------------
-- === Testing === --
---------------------

main :: IO ()
main = Graph.encodeAndEval @ShellCompiler $ Scheduler.evalT $ do
    p <- Path.parseAbsDir "/Users/marcinkostrzewa/code/luna/stdlib/Std"
    sourcesMap <- fmap Path.toFilePath . Bimap.toMapR <$> Project.findProjectSources p
    ModLoader.init @ShellCompiler
    Scheduler.registerAttr @Unit.UnitRefsMap
    Scheduler.enableAttrByType @Unit.UnitRefsMap
    ModLoader.loadUnit sourcesMap [] (convert ("Std.OAuth" :: IR.Name))
    Unit.UnitRefsMap mods <- Scheduler.getAttr
    print mods

    units <- for mods $ UnitMap.mapUnit @ShellCompiler . view Unit.root

    let unitResolvers   = Map.mapWithKey Res.resolverFromUnit units
        importResolvers = Map.mapWithKey (Res.resolverForUnit unitResolvers) $ view Unit.imports <$> mods

    for (Map.toList importResolvers) $ \(unitName, resolver) -> do
        print unitName
        let Just (Unit.Unit (Def.DefsMap defs) classes) = Map.lookup unitName units
        for defs $ \(Def.Documented _ fun) -> do
            PreprocessDef.preprocessDef @ShellCompiler resolver fun
        for classes $ \(Def.Documented _ (Class.Class _ (Def.DefsMap meths))) -> do
            for meths $ \(Def.Documented _ fun) -> do
                PreprocessDef.preprocessDef @ShellCompiler resolver fun
    return ()








    {-let [(_, r)] = Map.toList mods-}

    {-Scheduler.setAttr $ Root $ Layout.relayout r-}
    {-Scheduler.setAttr $ VisName "lel"-}
    {-Scheduler.registerPass @ShellCompiler @VisPass-}
    {-Scheduler.runPassByType @VisPass-}


    {-for_ mods $ \mod -> do-}
        {-Scheduler.setAttr $ Root $ Layout.relayout mod-}
        {-Scheduler.runPassByType @UnitMap.UnitMapper-}
        {-UnitMap.PartiallyMappedUnit m c <- Scheduler.getAttr-}
        {-print m-}
        {-print c-}

-- stdlibPath :: IO FilePath
-- stdlibPath = do
--     env     <- Map.fromList <$> System.getEnvironment
--     exePath <- fst <$> splitExecutablePath
--     let (<</>>)        = (FilePath.</>)  -- purely for convenience,
--                                          -- because </> is defined elswhere
--         parent         = let p = FilePath.takeDirectory
--                          in \x -> if FilePath.hasTrailingPathSeparator x
--                                   then p (p x)
--                                   else p x
--         defaultStdPath = (parent . parent . parent $ exePath)
--                     <</>> "config"
--                     <</>> "env"
--         envStdPath     = Map.lookup Project.lunaRootEnv env
--         stdPath        = fromMaybe defaultStdPath envStdPath <</>> "Std"
--     exists <- doesDirectoryExist stdPath
--     if exists
--         then putStrLn $ "Found the standard library at: " <> stdPath
--         else die $ "Standard library not found. Set the "
--                 <> Project.lunaRootEnv
--                 <> " environment variable"
--     return stdPath

